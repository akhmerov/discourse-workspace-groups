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

      chat_channel = channel.category_channel
      chat_channel&.remove(user)
      Chat::Publisher.publish_kick_users(chat_channel.id, [user.id]) if chat_channel.present?
      channel.workspace_group.remove(user)

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
