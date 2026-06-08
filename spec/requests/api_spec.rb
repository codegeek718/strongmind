require "rails_helper"

RSpec.describe "API", type: :request do
  describe "GET /up" do
    it "reports ok" do
      get "/up"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("ok")
    end
  end

  describe "GET /api/stats" do
    it "returns aggregate counts" do
      create_list(:push_event, 3)
      get "/api/stats"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["push_events"]).to eq(3)
    end
  end

  describe "GET /api/push_events" do
    it "lists recent events with queryable fields" do
      create(:push_event, github_event_id: "abc", ref: "refs/heads/main")
      get "/api/push_events"
      body = JSON.parse(response.body)
      expect(body["count"]).to eq(1)
      expect(body["push_events"].first["ref"]).to eq("refs/heads/main")
    end

    it "returns a single event with its raw payload" do
      create(:push_event, github_event_id: "abc")
      get "/api/push_events/abc"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("raw_payload")
    end

    it "404s for an unknown event" do
      get "/api/push_events/does-not-exist"
      expect(response).to have_http_status(:not_found)
    end
  end
end
