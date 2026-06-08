module Api
  class RepositoriesController < ApplicationController
    def index
      repos = Repository.order(updated_at: :desc).limit([params.fetch(:limit, 25).to_i, 100].min)
      render json: { count: repos.size, repositories: repos.as_json(except: :raw) }
    end

    def show
      repo = Repository.find_by!(github_id: params[:github_id])
      render json: repo
    end
  end
end
