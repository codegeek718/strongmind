class CreateActors < ActiveRecord::Migration[7.1]
  def change
    create_table :actors do |t|
      t.bigint :github_id, null: false

      # from the event payload
      t.string :login
      t.string :display_login
      t.string :gravatar_id
      t.string :url
      t.string :avatar_url

      # from enrichment
      t.string :html_url
      t.string :node_id
      t.string :user_type
      t.string :name
      t.string :company
      t.string :location
      t.string :blog
      t.text   :bio
      t.integer :public_repos
      t.integer :followers
      t.integer :following

      t.jsonb :raw, null: false, default: {}
      t.string :etag
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :actors, :github_id, unique: true
    add_index :actors, :login
  end
end
