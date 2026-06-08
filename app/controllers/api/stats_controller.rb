module Api
  class StatsController < ApplicationController
    def show
      render json: {
        push_events: PushEvent.count,
        push_events_enriched: PushEvent.enriched.count,
        push_events_pending_enrichment: PushEvent.pending_enrichment.count,
        actors: Actor.count,
        actors_fetched: Actor.where.not(fetched_at: nil).count,
        repositories: Repository.count,
        repositories_fetched: Repository.where.not(fetched_at: nil).count,
        latest_event_at: PushEvent.maximum(:event_created_at),
        rate_limit: RateLimiter.new.snapshot
      }
    end
  end
end
