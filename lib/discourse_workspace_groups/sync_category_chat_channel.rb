# frozen_string_literal: true

require "set"

module ::DiscourseWorkspaceGroups
  class SyncCategoryChatChannel
    CHAT_DESCRIPTION_MAX_LENGTH = 500

    attr_reader :category, :user, :sync_all_members

    def initialize(category:, user: nil, sync_all_members: true)
      @category = category
      @user = user
      @sync_all_members = sync_all_members
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

      sync_group_memberships(chat_channel) if sync_all_members

      if user.present?
        ensure_chat_membership(chat_channel, user)
      end

      sync_archive_status(chat_channel)

      chat_channel
    end

    def group_users
      category.workspace_group&.users&.to_a || []
    end

    def sync_group_memberships(chat_channel)
      existing_user_ids = chat_channel.user_chat_channel_memberships.pluck(:user_id).to_set

      group_users.each do |group_user|
        next if existing_user_ids.include?(group_user.id)

        ensure_chat_membership(chat_channel, group_user)
        existing_user_ids.add(group_user.id)
      end
    end

    def ensure_chat_membership(chat_channel, candidate_user)
      return if candidate_user.blank?
      return if !Guardian.new(candidate_user).can_join_chat_channel?(chat_channel)

      chat_channel.add(candidate_user)
    end

    def sync_archive_status(chat_channel)
      target_status = category.workspace_archived? ? "read_only" : "open"
      return if chat_channel.status == target_status

      chat_channel.update!(status: target_status)
      Chat::Publisher.publish_channel_status(chat_channel)
    end

    def desired_slug
      parent_slug = category.parent_category&.slug.presence
      category_slug = category.slug.presence || Slug.for(category.name, "")
      base =
        if parent_slug.present? && category_slug.start_with?("#{parent_slug}-")
          category_slug
        else
          [parent_slug, category_slug].compact.join("-")
        end

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
