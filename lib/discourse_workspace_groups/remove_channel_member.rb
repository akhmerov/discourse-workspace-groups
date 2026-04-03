# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class RemoveChannelMember
    attr_reader :channel, :acting_user, :target_user

    def initialize(channel:, acting_user:, target_user:)
      @channel = channel
      @acting_user = acting_user
      @target_user = target_user
    end

    def call
      validate!

      channel.workspace_group.remove(target_user)
      channel
    end

    private

    def validate!
      raise Discourse::InvalidAccess if acting_user.blank?
      raise Discourse::InvalidAccess if !channel&.workspace_channel?
      raise Discourse::InvalidAccess if !DiscourseWorkspaceGroups.can_manage_workspace_channel?(channel, acting_user)
      raise Discourse::InvalidAccess if target_user.blank?
      raise Discourse::InvalidAccess if target_user.id == acting_user.id
      raise Discourse::InvalidAccess if !DiscourseWorkspaceGroups.can_remove_channel_group_member?(channel.workspace_group, target_user)
    end
  end
end
