# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class SyncCategoryChatChannel
    CHAT_DESCRIPTION_MAX_LENGTH = 500

    attr_reader :category, :user

    def initialize(category:, user: nil)
      @category = category
      @user = user
    end

    def call
      return if category.blank? || !category.workspace_channel?
      return if !SiteSetting.chat_enabled || !SiteSetting.enable_public_channels

      slug = desired_slug
      chat_channel = category.category_channel

      if chat_channel.blank?
        chat_channel =
          category.create_chat_channel!(
            name: category.name,
            description: chat_description,
            slug: slug,
            auto_join_users: false,
            threading_enabled: true,
          )
      else
        attrs = {}
        attrs[:name] = category.name if chat_channel.name != category.name
        attrs[:description] = chat_description if chat_channel.description != chat_description
        attrs[:slug] = slug if chat_channel.slug != slug
        attrs[:auto_join_users] = false if chat_channel.auto_join_users?
        attrs[:threading_enabled] = true if !chat_channel.threading_enabled?
        chat_channel.update!(attrs) if attrs.present?
      end

      group_users.each do |group_user|
        refreshed_user = User.find_by(id: group_user.id)
        next if refreshed_user.blank?
        next if !Guardian.new(refreshed_user).can_join_chat_channel?(chat_channel)

        chat_channel.add(refreshed_user)
      end

      if user.present?
        refreshed_user = User.find_by(id: user.id)

        if refreshed_user.present? && Guardian.new(refreshed_user).can_join_chat_channel?(chat_channel)
          chat_channel.add(refreshed_user)
        end
      end

      sync_archive_status(chat_channel)

      chat_channel
    end

    def group_users
      category.workspace_group&.users&.to_a || []
    end

    def sync_archive_status(chat_channel)
      target_status = category.workspace_archived? ? "read_only" : "open"
      return if chat_channel.status == target_status

      chat_channel.update!(status: target_status)
      Chat::Publisher.publish_channel_status(chat_channel)
    end

    def desired_slug
      base =
        [
          category.parent_category&.slug.presence,
          category.slug.presence || Slug.for(category.name, ""),
        ].compact.join("-")

      suffix = "-#{category.id}"
      "#{base.first(100 - suffix.length)}#{suffix}"
    end

    def chat_description
      description = category.description_text.to_s.strip
      return if description.blank?
      return description if description.grapheme_clusters.size <= CHAT_DESCRIPTION_MAX_LENGTH

      "#{description.grapheme_clusters.first(CHAT_DESCRIPTION_MAX_LENGTH - 1).join}\u2026"
    end
  end
end
