class CreatePushEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :push_events do |t|
      t.string :github_event_id, null: false
      t.string :event_type, null: false, default: "PushEvent"

      t.bigint :repository_id
      t.string :repository_name
      t.bigint :push_id
      t.string :ref
      t.string :head
      t.string :before
      t.integer :commit_size
      t.integer :distinct_size
      t.bigint :actor_id
      t.string :actor_login
      t.datetime :event_created_at

      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :enriched_at

      t.timestamps
    end

    add_index :push_events, :github_event_id, unique: true
    add_index :push_events, :repository_id
    add_index :push_events, :actor_id
    add_index :push_events, :push_id
    add_index :push_events, :event_created_at
  end
end
