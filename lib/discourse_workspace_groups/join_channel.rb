# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class JoinChannel
    attr_reader :channel, :user

    def initialize(channel:, user:)
      @channel = channel
      @user = user
    end

    def call
      validate!

      channel.workspace_group.add(user)
      chat_channel = DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: channel).call
      Chat::Publisher.publish_new_channel(chat_channel, [user.id]) if chat_channel.present?

      channel
    end

    private

    def validate!
      raise Discourse::InvalidAccess if user.blank?
      raise Discourse::InvalidAccess if !channel&.workspace_channel?
      raise Discourse::InvalidAccess if channel.workspace_visibility != VISIBILITY_PUBLIC
      raise Discourse::InvalidAccess if channel.workspace_group.blank?
      raise Discourse::InvalidAccess if channel.workspace_group.users.exists?(id: user.id)

      workspace = channel.workspace_parent_category
      raise Discourse::InvalidAccess if !workspace&.workspace_root?
      return if user.admin?
      raise Discourse::InvalidAccess if !workspace.workspace_group.users.exists?(id: user.id)
    end
  end
end
