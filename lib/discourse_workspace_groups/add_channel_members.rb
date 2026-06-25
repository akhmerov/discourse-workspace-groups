# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class AddChannelMembers
    attr_reader :channel, :acting_user, :users

    def initialize(channel:, acting_user:, users:)
      @channel = channel
      @acting_user = acting_user
      @users = Array(users).compact.uniq { |user| user.id }
    end

    def call
      validate!

      users.each do |user|
        next if channel.workspace_group.users.exists?(id: user.id)

        channel.workspace_group.add(user)
      end

      channel
    end

    private

    def validate!
      raise Discourse::InvalidAccess if acting_user.blank?
      raise Discourse::InvalidAccess if !channel&.workspace_channel?
      raise Discourse::InvalidAccess if !DiscourseWorkspaceGroups.can_add_workspace_channel_members?(channel, acting_user)
      raise Discourse::InvalidParameters.new(:usernames) if users.blank?

      return if DiscourseWorkspaceGroups.can_manage_workspace_channel?(channel, acting_user)

      workspace_group = channel.workspace_parent_category&.workspace_group
      raise Discourse::InvalidAccess if workspace_group.blank?
      raise Discourse::InvalidAccess if users.any? { |user| !DiscourseWorkspaceGroups.group_member?(workspace_group, user) }
    end
  end
end
