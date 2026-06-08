module Api
  class ActorsController < ApplicationController
    def index
      actors = Actor.order(updated_at: :desc).limit([params.fetch(:limit, 25).to_i, 100].min)
      render json: { count: actors.size, actors: actors.as_json(except: :raw) }
    end

    def show
      actor = Actor.find_by!(github_id: params[:github_id])
      render json: actor
    end
  end
end
