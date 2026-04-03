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
      raise Discourse::InvalidAccess if !DiscourseWorkspaceGroups.can_manage_workspace_channel?(channel, acting_user)
      raise Discourse::InvalidParameters.new(:usernames) if users.blank?
    end
  end
end
