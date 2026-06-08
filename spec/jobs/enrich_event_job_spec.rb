require "rails_helper"

RSpec.describe EnrichEventJob do
  let(:actor_url) { "https://api.github.com/users/octocat" }
  let(:repo_url) { "https://api.github.com/repos/octocat/Hello-World" }
  let(:actor_data) { JSON.parse(file_fixture("actor.json").read) }
  let(:repo_data) { JSON.parse(file_fixture("repository.json").read) }

  let!(:push_event) do
    create(:push_event, github_event_id: "evt-1", actor_id: 583_231, repository_id: 1_296_269)
  end

  before do
    Actor.create!(github_id: 583_231, login: "octocat", url: actor_url)
    Repository.create!(github_id: 1_296_269, name: "octocat/Hello-World", url: repo_url)
  end

  def ok(data)
    GithubClient::Result.new(status: 200, data: data, headers: {}, etag: '"x"')
  end

  def build_job(budget: true, client:)
    job = described_class.new
    rl = instance_double(RateLimiter, can_spend?: budget)
    allow(job).to receive(:rate_limiter).and_return(rl)
    allow(job).to receive(:client).and_return(client)
    job
  end

  it "fetches actor and repository and persists deep fields" do
    client = instance_double(GithubClient)
    allow(client).to receive(:get).with(actor_url).and_return(ok(actor_data))
    allow(client).to receive(:get).with(repo_url).and_return(ok(repo_data))

    build_job(client: client).perform("evt-1")

    actor = Actor.find_by(github_id: 583_231)
    expect(actor.name).to eq("The Octocat")
    expect(actor.followers).to eq(12_000)
    expect(actor.fetched_at).to be_present

    repo = Repository.find_by(github_id: 1_296_269)
    expect(repo.full_name).to eq("octocat/Hello-World")
    expect(repo.stargazers_count).to eq(80)
    expect(repo.fetched_at).to be_present

    expect(push_event.reload.enriched_at).to be_present
  end

  it "skips fetching resources that were fetched within the TTL" do
    Actor.find_by(github_id: 583_231).update!(fetched_at: 1.hour.ago)
    Repository.find_by(github_id: 1_296_269).update!(fetched_at: 1.hour.ago)

    client = instance_double(GithubClient)
    expect(client).not_to receive(:get)

    build_job(client: client).perform("evt-1")
  end

  it "does not spend quota when the reserve budget is exhausted" do
    client = instance_double(GithubClient)
    expect(client).not_to receive(:get)

    build_job(budget: false, client: client).perform("evt-1")
    expect(Actor.find_by(github_id: 583_231).fetched_at).to be_nil
  end

  it "defers (reschedules) instead of failing when rate limited" do
    client = instance_double(GithubClient)
    allow(client).to receive(:get).and_raise(GithubClient::RateLimitError.new("limited", retry_after: 90))

    build_job(client: client).perform("evt-1")

    expect(described_class.jobs.size).to eq(1)
    expect(push_event.reload.enriched_at).to be_nil
  end
end
