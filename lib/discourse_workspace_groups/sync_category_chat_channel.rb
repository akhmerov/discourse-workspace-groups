# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class SyncCategoryChatChannel
    attr_reader :category, :user

    def initialize(category:, user: nil)
      @category = category
      @user = user
    end

    def call
      return if category.blank? || !category.workspace_channel?
      return if !SiteSetting.chat_enabled || !SiteSetting.enable_public_channels

      chat_channel = category.category_channel

      if chat_channel.blank?
        chat_channel =
          category.create_chat_channel!(
            name: category.name,
            description: category.description,
            slug: category.slug,
            auto_join_users: true,
            threading_enabled: true,
          )
      else
        attrs = {}
        attrs[:name] = category.name if chat_channel.name != category.name
        attrs[:description] = category.description if chat_channel.description != category.description
        attrs[:slug] = category.slug if chat_channel.slug != category.slug
        attrs[:auto_join_users] = true if !chat_channel.auto_join_users?
        attrs[:threading_enabled] = true if !chat_channel.threading_enabled?
        chat_channel.update!(attrs) if attrs.present?
      end

      if user.present? && user.guardian.can_join_chat_channel?(chat_channel)
        chat_channel.add(user)
      end

      Chat::AutoJoinChannels.call(params: { channel_id: chat_channel.id }) if chat_channel.auto_join_users?
      chat_channel
    end
  end
end
