require "rails_helper"

RSpec.describe RateLimiter do
  subject(:limiter) { described_class.new(redis: FakeRedis.new) }

  describe "#record and #snapshot" do
    it "captures limit/remaining/reset from response headers (any case)" do
      reset = 1_900_000_000
      limiter.record("X-RateLimit-Limit" => "60", "X-RateLimit-Remaining" => "42", "X-RateLimit-Reset" => reset.to_s)

      snap = limiter.snapshot
      expect(snap[:limit]).to eq(60)
      expect(snap[:remaining]).to eq(42)
      expect(snap[:reset_at]).to eq(Time.zone.at(reset))
    end
  end

  describe "#can_spend?" do
    it "allows when remaining is above the reserve" do
      limiter.record("x-ratelimit-remaining" => "30", "x-ratelimit-reset" => 1_900_000_000.to_s)
      expect(limiter.can_spend?(reserve: 15)).to be(true)
    end

    it "blocks when remaining is at or below the reserve" do
      limiter.record("x-ratelimit-remaining" => "10", "x-ratelimit-reset" => 1_900_000_000.to_s)
      expect(limiter.can_spend?(reserve: 15)).to be(false)
    end

    it "allows when budget is unknown (we learn from the response)" do
      expect(limiter.can_spend?(reserve: 15)).to be(true)
    end
  end

  describe "ETag storage" do
    it "round-trips an ETag per URL" do
      limiter.store_etag("https://api.github.com/events", '"abc123"')
      expect(limiter.etag_for("https://api.github.com/events")).to eq('"abc123"')
    end
  end
end
