# frozen_string_literal: true

class AddWorkspaceVoiceGuestPolicy < ActiveRecord::Migration[7.2]
  def change
    add_column :workspace_voice_bindings, :allow_guests, :boolean, null: false, default: true
  end
end
