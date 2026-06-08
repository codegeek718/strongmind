require "rails_helper"

RSpec.describe GithubClient do
  let(:limiter) { RateLimiter.new(redis: FakeRedis.new) }
  subject(:client) { described_class.new(rate_limiter: limiter) }

  let(:url) { "https://api.github.com/events" }

  it "parses a 200 response and records rate-limit headers" do
    stub_request(:get, url).to_return(
      status: 200,
      body: [{ "id" => "1", "type" => "PushEvent" }].to_json,
      headers: {
        "Content-Type" => "application/json",
        "ETag" => '"abc"',
        "X-RateLimit-Limit" => "60",
        "X-RateLimit-Remaining" => "59",
        "X-RateLimit-Reset" => "1900000000"
      }
    )

    result = client.get(url)

    expect(result.status).to eq(200)
    expect(result.data.first["type"]).to eq("PushEvent")
    expect(limiter.snapshot[:remaining]).to eq(59)
    # ETag is stored for the next conditional request.
    expect(limiter.etag_for(url)).to eq('"abc"')
  end

  it "sends a stored ETag and handles a free 304" do
    limiter.store_etag(url, '"abc"')
    stub = stub_request(:get, url).with(headers: { "If-None-Match" => '"abc"' }).to_return(status: 304)

    result = client.get(url)

    expect(result).to be_not_modified
    expect(result.data).to be_nil
    expect(stub).to have_been_requested
  end

  it "raises RateLimitError when remaining is zero" do
    stub_request(:get, url).to_return(
      status: 403,
      headers: { "X-RateLimit-Remaining" => "0", "X-RateLimit-Reset" => "1900000000" }
    )

    expect { client.get(url) }.to raise_error(GithubClient::RateLimitError) do |e|
      expect(e.retry_after).to be >= 1
    end
  end

  it "raises ServerError on 5xx (retryable)" do
    stub_request(:get, url).to_return(status: 502)
    expect { client.get(url) }.to raise_error(GithubClient::ServerError)
  end

  it "raises ClientError on 404 (non-retryable)" do
    stub_request(:get, url).to_return(status: 404)
    expect { client.get(url) }.to raise_error(GithubClient::ClientError)
  end
end
