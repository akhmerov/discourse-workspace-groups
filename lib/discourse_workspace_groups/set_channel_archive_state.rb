# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class SetChannelArchiveState
    attr_reader :channel, :user, :archived

    def initialize(channel:, user:, archived:)
      @channel = channel
      @user = user
      @archived = archived
    end

    def call
      validate!

      if channel.workspace_archived? != archived
        channel.custom_fields[WORKSPACE_ARCHIVED] = archived
        channel.save_custom_fields(true)
      end

      DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: channel, user: user).call
      channel
    end

    private

    def validate!
      raise Discourse::InvalidAccess if user.blank?
      raise Discourse::InvalidAccess if !channel&.workspace_channel?
      raise Discourse::InvalidAccess if !DiscourseWorkspaceGroups.can_manage_workspace_channel?(channel, user)
    end
  end
end
