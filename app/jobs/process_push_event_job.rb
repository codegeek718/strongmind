# Stores one raw event plus its inline actor/repo data, then queues enrichment.
# Safe to run more than once for the same event (upserts on the GitHub ids).
class ProcessPushEventJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 5

  def perform(event)
    event = event.is_a?(String) ? JSON.parse(event) : event

    unless event.is_a?(Hash) && event["id"].present?
      logger.warn({ source: "process", message: "skipping event without id" }.to_json)
      return
    end

    save_event(event)
    save_actor(event["actor"])
    save_repository(event["repo"])
    enqueue_enrichment(event["id"])

    logger.info({ source: "process", message: "saved", github_event_id: event["id"],
                  repo: event.dig("repo", "name") }.to_json)
  rescue ActiveRecord::ActiveRecordError => e
    logger.error({ source: "process", message: "db error", github_event_id: event && event["id"],
                   error: e.message }.to_json)
    raise
  end

  private

  def save_event(event)
    # enriched_at is left out so re-runs don't wipe it.
    PushEvent.upsert(PushEvent.from_event(event), unique_by: :github_event_id)
  end

  def save_actor(actor)
    return if actor.blank? || actor["id"].blank?

    Actor.upsert(
      {
        github_id: actor["id"],
        login: actor["login"],
        display_login: actor["display_login"],
        gravatar_id: actor["gravatar_id"],
        url: actor["url"],
        avatar_url: actor["avatar_url"]
      },
      unique_by: :github_id
    )
  end

  def save_repository(repo)
    return if repo.blank? || repo["id"].blank?

    Repository.upsert(
      {
        github_id: repo["id"],
        name: repo["name"],
        url: repo["url"]
      },
      unique_by: :github_id
    )
  end

  def enqueue_enrichment(github_event_id)
    return unless PushEvent.where(github_event_id: github_event_id).pick(:enriched_at).nil?

    EnrichEventJob.perform_async(github_event_id)
  end
end
