# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class SyncChannelGroupChatMembership
    attr_reader :user, :group

    def initialize(user:, group:)
      @user = user
      @group = group
    end

    def call
      return if user.blank? || group.blank?

      category = DiscourseWorkspaceGroups.workspace_channel_category_for_group(group)
      return if category.blank?

      existing_chat_channel = category.category_channel
      had_membership = existing_chat_channel&.membership_for(user).present?
      chat_channel = DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: category, user: user).call

      return if chat_channel.blank? || had_membership

      membership = chat_channel.membership_for(user)
      return if membership.blank?

      Chat::Publisher.publish_new_channel(chat_channel, [user.id])
      chat_channel
    end
  end
end
