require "rails_helper"

RSpec.describe EventsPoller do
  let(:limiter) { RateLimiter.new(redis: FakeRedis.new) }
  let(:client) { instance_double(GithubClient) }
  subject(:poller) { described_class.new(client: client, rate_limiter: limiter) }

  let(:events) { JSON.parse(file_fixture("github_events.json").read) }

  def result(status:, data: nil, headers: {})
    GithubClient::Result.new(status: status, data: data, headers: headers, etag: nil)
  end

  it "enqueues only PushEvents for processing" do
    allow(client).to receive(:get).and_return(result(status: 200, data: events, headers: { "x-poll-interval" => "60" }))

    poller.cycle

    expect(ProcessPushEventJob.jobs.size).to eq(1)
    enqueued = ProcessPushEventJob.jobs.first["args"].first
    expect(enqueued["type"]).to eq("PushEvent")
    expect(enqueued["id"]).to eq("1000000001")
  end

  it "does nothing on a 304 (not modified)" do
    allow(client).to receive(:get).and_return(result(status: 304))
    poller.cycle
    expect(ProcessPushEventJob.jobs).to be_empty
  end

  it "returns at least the minimum poll interval" do
    allow(client).to receive(:get).and_return(result(status: 200, data: events, headers: { "x-poll-interval" => "1" }))
    expect(poller.cycle).to be >= ENV.fetch("MIN_POLL_INTERVAL_SECONDS", 60).to_i
  end

  it "backs off (does not raise) when rate limited" do
    allow(client).to receive(:get).and_raise(GithubClient::RateLimitError.new("limited", retry_after: 120))
    expect { @interval = poller.cycle }.not_to raise_error
    expect(@interval).to be >= 120
  end

  it "survives unexpected errors without crashing the loop" do
    allow(client).to receive(:get).and_raise(StandardError, "boom")
    expect { poller.cycle }.not_to raise_error
  end
end
