require "rails_helper"

RSpec.describe ProcessPushEventJob do
  let(:event) { JSON.parse(file_fixture("github_events.json").read).first }

  it "persists structured fields, raw payload, and inline actor/repo" do
    described_class.new.perform(event)

    pe = PushEvent.find_by(github_event_id: "1000000001")
    expect(pe).to be_present
    expect(pe.repository_id).to eq(1_296_269)
    expect(pe.repository_name).to eq("octocat/Hello-World")
    expect(pe.push_id).to eq(987_654_321)
    expect(pe.ref).to eq("refs/heads/main")
    expect(pe.head).to eq("a" * 40)
    expect(pe.before).to eq("b" * 40)
    expect(pe.raw_payload["type"]).to eq("PushEvent")

    expect(Actor.find_by(github_id: 583_231).login).to eq("octocat")
    expect(Repository.find_by(github_id: 1_296_269).name).to eq("octocat/Hello-World")
  end

  it "does not duplicate rows when run again with the same event" do
    expect do
      described_class.new.perform(event)
      described_class.new.perform(event)
    end.to change(PushEvent, :count).by(1)

    expect(Actor.count).to eq(1)
    expect(Repository.count).to eq(1)
  end

  it "enqueues enrichment exactly once for a fresh event" do
    described_class.new.perform(event)
    expect(EnrichEventJob.jobs.size).to eq(1)
  end

  it "does not re-enqueue enrichment for an already-enriched event" do
    described_class.new.perform(event)
    PushEvent.update_all(enriched_at: Time.current)
    EnrichEventJob.clear

    described_class.new.perform(event)
    expect(EnrichEventJob.jobs).to be_empty
  end

  it "handles malformed events without raising" do
    expect { described_class.new.perform({ "no_id" => true }) }.not_to raise_error
    expect(PushEvent.count).to eq(0)
  end
end
