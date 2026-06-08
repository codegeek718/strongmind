# In-memory Redis stand-in so the rate limiter specs don't need a running Redis.
class FakeRedis
  def initialize
    @store = {}
  end

  def get(key)
    @store[key]
  end

  def set(key, value)
    @store[key] = value.to_s
    "OK"
  end

  def flushdb
    @store.clear
  end
end
