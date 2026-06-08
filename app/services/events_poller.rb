# Polls the public events feed, keeps the PushEvents, and hands each one to a
# job for persistence + enrichment. It only fetches and enqueues; the DB work
# happens in the workers.
class EventsPoller
  EVENTS_URL = "https://api.github.com/events".freeze

  def initialize(client: GithubClient.new, logger: Rails.logger, rate_limiter: RateLimiter.new)
    @client = client
    @logger = logger
    @rate_limiter = rate_limiter
    @min_interval = ENV.fetch("MIN_POLL_INTERVAL_SECONDS", 60).to_i
    @stopping = false
  end

  # `cycles` bounds the run (nil = until stopped).
  def run(continuous: true, cycles: nil)
    install_signal_handlers if continuous
    completed = 0
    log(:info, "poller starting", min_interval: @min_interval, continuous: continuous)

    loop do
      interval = cycle
      completed += 1
      break if @stopping
      break if cycles && completed >= cycles
      break unless continuous

      sleep_for(interval)
    end

    log(:info, "poller stopped", cycles_completed: completed)
    completed
  end

  # One poll. Returns how long to wait before the next one. Never raises:
  # any failure becomes a backoff interval so the loop keeps running.
  def cycle
    result = @client.get(EVENTS_URL)

    if result.not_modified?
      log(:info, "no new events (304)", **rate_info)
      return poll_interval(result.headers)
    end

    events = Array(result.data)
    pushes = events.select { |e| e.is_a?(Hash) && e["type"] == "PushEvent" }

    enqueued = enqueue(pushes)
    log(:info, "cycle complete", events_seen: events.size, push_events: pushes.size,
        enqueued: enqueued, **rate_info)

    poll_interval(result.headers)
  rescue GithubClient::RateLimitError => e
    wait = [e.retry_after, @min_interval].max
    log(:warn, "rate limited; backing off", retry_after_s: e.retry_after, sleeping_s: wait, **rate_info)
    wait
  rescue GithubClient::ServerError => e
    log(:warn, "transient error; will retry", error: e.message)
    @min_interval
  rescue => e
    log(:error, "unexpected error; continuing", error: e.message, error_class: e.class.name)
    @min_interval
  end

  private

  def enqueue(events)
    events.count do |event|
      ProcessPushEventJob.perform_async(event)
      true
    rescue => e
      log(:error, "failed to enqueue", github_event_id: event["id"], error: e.message)
      false
    end
  end

  def poll_interval(headers)
    suggested = headers && headers["x-poll-interval"].to_i
    [suggested.to_i, @min_interval].max
  end

  def rate_info
    snap = @rate_limiter.snapshot
    { rate_remaining: snap[:remaining], rate_limit: snap[:limit], rate_reset_at: snap[:reset_at]&.iso8601 }
  end

  def sleep_for(seconds)
    slept = 0
    while slept < seconds && !@stopping
      nap = [1, seconds - slept].min
      sleep(nap)
      slept += nap
    end
  end

  def install_signal_handlers
    %w[INT TERM].each { |sig| trap(sig) { @stopping = true } }
  end

  def log(level, message, **fields)
    @logger.public_send(level, { source: "poller", message: message, **fields }.to_json)
  end
end
