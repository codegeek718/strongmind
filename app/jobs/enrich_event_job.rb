# Fetches the actor and repo behind an event. This is where we spend API quota,
# so it skips anything fetched recently, only runs when budget is left, and
# defers itself if the limit is hit.
class EnrichEventJob
  include Sidekiq::Job

  sidekiq_options queue: :enrichment, retry: 5

  def perform(github_event_id)
    push_event = PushEvent.find_by(github_event_id: github_event_id)
    return if push_event.nil?

    reserve = ENV.fetch("ENRICHMENT_RATE_RESERVE", 15).to_i
    ttl = ENV.fetch("ENRICHMENT_TTL_HOURS", 24).to_i.hours

    enrich_actor(push_event.actor_id, reserve:, ttl:)
    enrich_repository(push_event.repository_id, reserve:, ttl:)

    push_event.update_column(:enriched_at, Time.current)
    logger.info({ source: "enrich", message: "done", github_event_id: github_event_id }.to_json)
  rescue GithubClient::RateLimitError => e
    EnrichEventJob.perform_in(e.retry_after, github_event_id)
    logger.warn({ source: "enrich", message: "rate limited; deferred",
                  github_event_id: github_event_id, retry_after_s: e.retry_after }.to_json)
  rescue GithubClient::ClientError => e
    # e.g. deleted user/repo: mark done so we don't keep retrying.
    push_event&.update_column(:enriched_at, Time.current)
    logger.warn({ source: "enrich", message: "client error", github_event_id: github_event_id,
                  error: e.message }.to_json)
  end

  private

  def enrich_actor(actor_id, reserve:, ttl:)
    return if actor_id.blank?

    actor = Actor.find_by(github_id: actor_id)
    return if actor&.fresh?(ttl)

    url = actor&.url.presence || "https://api.github.com/user/#{actor_id}"
    return unless rate_limiter.can_spend?(reserve:)

    result = client.get(url)
    return touch(actor) if result.not_modified?

    save_actor(actor_id, result.data, result.etag)
  end

  def enrich_repository(repository_id, reserve:, ttl:)
    return if repository_id.blank?

    repo = Repository.find_by(github_id: repository_id)
    return if repo&.fresh?(ttl)

    url = repo&.url.presence || "https://api.github.com/repositories/#{repository_id}"
    return unless rate_limiter.can_spend?(reserve:)

    result = client.get(url)
    return touch(repo) if result.not_modified?

    save_repository(repository_id, result.data, result.etag)
  end

  def save_actor(github_id, data, etag)
    return if data.blank?

    Actor.upsert(
      {
        github_id: github_id,
        login: data["login"],
        avatar_url: data["avatar_url"],
        gravatar_id: data["gravatar_id"],
        url: data["url"],
        html_url: data["html_url"],
        node_id: data["node_id"],
        user_type: data["type"],
        name: data["name"],
        company: data["company"],
        location: data["location"],
        blog: data["blog"],
        bio: data["bio"],
        public_repos: data["public_repos"],
        followers: data["followers"],
        following: data["following"],
        raw: data,
        etag: etag,
        fetched_at: Time.current
      },
      unique_by: :github_id
    )
  end

  def save_repository(github_id, data, etag)
    return if data.blank?

    Repository.upsert(
      {
        github_id: github_id,
        full_name: data["full_name"],
        url: data["url"],
        html_url: data["html_url"],
        description: data["description"],
        language: data["language"],
        owner_login: data.dig("owner", "login"),
        owner_id: data.dig("owner", "id"),
        private: data.fetch("private", false),
        stargazers_count: data["stargazers_count"],
        watchers_count: data["watchers_count"],
        forks_count: data["forks_count"],
        open_issues_count: data["open_issues_count"],
        raw: data,
        etag: etag,
        fetched_at: Time.current
      },
      unique_by: :github_id
    )
  end

  def touch(record)
    record&.update_column(:fetched_at, Time.current)
  end

  def client
    @client ||= GithubClient.new(rate_limiter: rate_limiter)
  end

  def rate_limiter
    @rate_limiter ||= RateLimiter.new
  end
end
