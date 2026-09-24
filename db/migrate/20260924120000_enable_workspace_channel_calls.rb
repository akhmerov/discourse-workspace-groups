# frozen_string_literal: true

# Channel calls are now on by default. The channel settings dialog used to save
# voice_enabled on every save, so existing disabled bindings do not reliably record
# an opt-out; turn them all on and let managers opt channels out again.
class EnableWorkspaceChannelCalls < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      UPDATE workspace_voice_bindings
      SET enabled = TRUE, updated_at = NOW()
      WHERE source_type = 'category' AND enabled = FALSE
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
