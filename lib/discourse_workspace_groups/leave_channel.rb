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

      channel.category_channel&.remove(user)
      channel.workspace_group.remove(user)

      channel
    end

    private

    def validate!
      raise Discourse::InvalidAccess if user.blank?
      raise Discourse::InvalidAccess if !channel&.workspace_channel?
      raise Discourse::InvalidAccess if channel.workspace_group.blank?
      raise Discourse::InvalidAccess if !channel.workspace_group.users.exists?(id: user.id)
    end
  end
end
