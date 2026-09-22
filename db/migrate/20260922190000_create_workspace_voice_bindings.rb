# frozen_string_literal: true

class CreateWorkspaceVoiceBindings < ActiveRecord::Migration[7.2]
  def change
    create_table :workspace_voice_bindings do |t|
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.bigint :room_id
      t.boolean :enabled, null: false, default: false
      t.timestamps
    end
    add_index :workspace_voice_bindings, [:source_type, :source_id], unique: true
    add_index :workspace_voice_bindings, :room_id, unique: true
    add_check_constraint :workspace_voice_bindings,
                         "source_type IN ('category', 'dm')",
                         name: "workspace_voice_source_type"
  end
end
