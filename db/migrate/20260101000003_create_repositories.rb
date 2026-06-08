class CreateRepositories < ActiveRecord::Migration[7.1]
  def change
    create_table :repositories do |t|
      t.bigint :github_id, null: false

      # from the event payload
      t.string :name
      t.string :url

      # from enrichment
      t.string :full_name
      t.string :html_url
      t.text   :description
      t.string :language
      t.string :owner_login
      t.bigint :owner_id
      t.boolean :private, null: false, default: false
      t.integer :stargazers_count
      t.integer :watchers_count
      t.integer :forks_count
      t.integer :open_issues_count

      t.jsonb :raw, null: false, default: {}
      t.string :etag
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :repositories, :github_id, unique: true
    add_index :repositories, :name
  end
end
