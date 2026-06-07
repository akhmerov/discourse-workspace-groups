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

      existing_chat_channel = Chat::CategoryChannel.find_by(chatable: channel)
      had_membership = existing_chat_channel&.membership_for(user).present?
      chat_channel = DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: channel).call
      if channel.workspace_chat_enabled? && chat_channel.present? && !had_membership
        membership = chat_channel.membership_for(user)
        Chat::Publisher.publish_new_channel(chat_channel, [user.id]) if membership.present?
      end

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
