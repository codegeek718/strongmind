class Repository < ApplicationRecord
  validates :github_id, presence: true, uniqueness: true

  has_many :push_events, primary_key: :github_id, foreign_key: :repository_id, dependent: :nullify

  def fresh?(ttl)
    fetched_at.present? && fetched_at > ttl.ago
  end
end
