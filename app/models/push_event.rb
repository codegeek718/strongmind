class PushEvent < ApplicationRecord
  belongs_to :actor, primary_key: :github_id, foreign_key: :actor_id, optional: true
  belongs_to :repository, primary_key: :github_id, foreign_key: :repository_id, optional: true

  validates :github_event_id, presence: true, uniqueness: true

  scope :enriched, -> { where.not(enriched_at: nil) }
  scope :pending_enrichment, -> { where(enriched_at: nil) }
  scope :recent, -> { order(event_created_at: :desc) }

  # Maps a raw event hash to columns; tolerant of missing keys.
  def self.from_event(event)
    event = event.with_indifferent_access
    payload = event[:payload] || {}
    {
      github_event_id: event[:id],
      event_type: event[:type],
      repository_id: event.dig(:repo, :id),
      repository_name: event.dig(:repo, :name),
      push_id: payload[:push_id],
      ref: payload[:ref],
      head: payload[:head],
      before: payload[:before],
      commit_size: payload[:size],
      distinct_size: payload[:distinct_size],
      actor_id: event.dig(:actor, :id),
      actor_login: event.dig(:actor, :login),
      event_created_at: event[:created_at],
      raw_payload: event.to_h
    }
  end
end
