FactoryBot.define do
  factory :push_event do
    sequence(:github_event_id) { |n| (1_000_000_000 + n).to_s }
    event_type { "PushEvent" }
    repository_id { 1_296_269 }
    repository_name { "octocat/Hello-World" }
    push_id { 987_654_321 }
    ref { "refs/heads/main" }
    head { "a" * 40 }
    before { "b" * 40 }
    actor_id { 583_231 }
    actor_login { "octocat" }
    event_created_at { "2026-06-04T10:00:00Z" }
    raw_payload { { "id" => github_event_id, "type" => "PushEvent" } }
  end
end
