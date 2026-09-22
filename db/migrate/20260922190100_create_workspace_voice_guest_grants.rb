# frozen_string_literal: true

class CreateWorkspaceVoiceGuestGrants < ActiveRecord::Migration[7.2]
  def change
    create_table :workspace_voice_guest_grants do |t|
      t.bigint :voice_binding_id, null: false
      t.integer :user_id, null: false
      t.timestamps
    end
    add_index :workspace_voice_guest_grants, [:voice_binding_id, :user_id], unique: true,
              name: "workspace_voice_guest_grant_identity"
    add_foreign_key :workspace_voice_guest_grants, :workspace_voice_bindings,
                    column: :voice_binding_id, on_delete: :cascade
    add_foreign_key :workspace_voice_guest_grants, :users, on_delete: :cascade
  end
end
