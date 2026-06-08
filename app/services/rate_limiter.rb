# Tracks GitHub's rate-limit state in Redis so it's shared between the poller
# and the workers. Also stores per-URL ETags for conditional requests.
class RateLimiter
  REMAINING_KEY = "github:ratelimit:remaining".freeze
  LIMIT_KEY     = "github:ratelimit:limit".freeze
  RESET_KEY     = "github:ratelimit:reset".freeze
  ETAG_PREFIX   = "github:etag:".freeze

  def initialize(redis: nil, logger: Rails.logger)
    @redis = redis || Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/0"))
    @logger = logger
  end

  def record(headers)
    h = normalize(headers)
    with_redis do |r|
      r.set(LIMIT_KEY, h["x-ratelimit-limit"]) if h["x-ratelimit-limit"]
      r.set(REMAINING_KEY, h["x-ratelimit-remaining"]) if h["x-ratelimit-remaining"]
      r.set(RESET_KEY, h["x-ratelimit-reset"]) if h["x-ratelimit-reset"]
    end
  end

  def snapshot
    limit = remaining = reset = nil
    with_redis do |r|
      limit = r.get(LIMIT_KEY)
      remaining = r.get(REMAINING_KEY)
      reset = r.get(RESET_KEY)
    end
    {
      limit: limit&.to_i,
      remaining: remaining&.to_i,
      reset_at: reset && Time.zone.at(reset.to_i)
    }
  end

  # Once the window has passed we assume the budget is refreshed.
  def remaining
    snap = snapshot
    return nil if snap[:remaining].nil?
    return snap[:limit] || Float::INFINITY if snap[:reset_at] && snap[:reset_at] <= Time.current

    snap[:remaining]
  end

  # Leave `reserve` requests for the poller. Unknown budget means allow.
  def can_spend?(reserve:)
    rem = remaining
    rem.nil? || rem > reserve
  end

  def seconds_until_reset
    reset_at = snapshot[:reset_at]
    return 60 if reset_at.nil?

    [(reset_at - Time.current).ceil, 0].max
  end

  def etag_for(url)
    with_redis { |r| r.get(ETAG_PREFIX + url) }
  end

  def store_etag(url, etag)
    return if etag.blank?

    with_redis { |r| r.set(ETAG_PREFIX + url, etag) }
  end

  private

  def normalize(headers)
    headers.each_with_object({}) { |(k, v), acc| acc[k.to_s.downcase] = v }
  end

  def with_redis(&block)
    if @redis.respond_to?(:with)
      @redis.with(&block)
    else
      block.call(@redis)
    end
  end
end
