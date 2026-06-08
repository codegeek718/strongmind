module Api
  class PushEventsController < ApplicationController
    MAX_LIMIT = 100

    def index
      limit = [params.fetch(:limit, 25).to_i, MAX_LIMIT].min
      events = PushEvent.recent.limit(limit)
      events = events.where(repository_name: params[:repository]) if params[:repository].present?
      render json: { count: events.size, push_events: events.map { |e| summary(e) } }
    end

    def show
      event = PushEvent.find_by!(github_event_id: params[:github_event_id])
      render json: detail(event)
    end

    private

    def summary(event)
      {
        github_event_id: event.github_event_id,
        repository_id: event.repository_id,
        repository_name: event.repository_name,
        push_id: event.push_id,
        ref: event.ref,
        head: event.head,
        before: event.before,
        actor_login: event.actor_login,
        event_created_at: event.event_created_at,
        enriched_at: event.enriched_at
      }
    end

    def detail(event)
      summary(event).merge(
        actor: event.actor&.as_json(except: %i[created_at updated_at]),
        repository: event.repository&.as_json(except: %i[created_at updated_at]),
        raw_payload: event.raw_payload
      )
    end
  end
end
