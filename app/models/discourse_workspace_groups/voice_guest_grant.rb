# frozen_string_literal: true

module DiscourseWorkspaceGroups
  class VoiceGuestGrant < ActiveRecord::Base
    self.table_name = "workspace_voice_guest_grants"
    belongs_to :voice_binding
    belongs_to :user
  end
end
