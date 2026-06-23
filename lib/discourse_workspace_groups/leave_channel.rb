# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class LeaveChannel
    attr_reader :channel, :user

    def initialize(channel:, user:)
      @channel = channel
      @user = user
    end

    def call
      validate!

      DiscourseWorkspaceGroups::RemoveChannelGroupMember.new(
        group: channel.workspace_group,
        user: user,
      ).call

      channel
    end

    private

    def validate!
      raise Discourse::InvalidAccess if user.blank?
      raise Discourse::InvalidAccess if !channel&.workspace_channel?
      raise Discourse::InvalidAccess if channel.workspace_group.blank?
      raise Discourse::InvalidAccess if !DiscourseWorkspaceGroups.can_leave_channel_group?(channel.workspace_group, user)
    end
  end
end
