# frozen_string_literal: true

require "securerandom"

module ::DiscourseWorkspaceGroups
  class CreateChannel
    CATEGORY_SLUG_COLLISION_ATTEMPTS = 10
    TEMPORARY_CATEGORY_SLUG_PREFIX = "workspace-channel-pending"

    attr_reader :workspace, :user, :name, :description, :visibility, :channel_mode

    def initialize(workspace:, user:, name:, description:, visibility:, channel_mode: nil)
      @workspace = workspace
      @user = user
      @name = name.to_s.strip
      @description = description.to_s.strip
      @visibility = visibility.presence || VISIBILITY_PUBLIC
      @channel_mode = channel_mode.presence || CHANNEL_MODE_BOTH
    end

    def call
      validate!

      workspace_group = workspace.workspace_group
      channel_group = ensure_channel_group
      workspace.custom_fields[WORKSPACE_ENABLED] = true
      workspace.custom_fields[WORKSPACE_KIND] = WORKSPACE_KIND_ROOT
      workspace.custom_fields[WORKSPACE_GROUP_ID] = workspace_group.id
      workspace.set_permissions(root_permissions(workspace_group, channel_group.id))
      workspace.save!

      channel =
        Category.new(
          name: name,
          slug: temporary_category_slug,
          color: workspace.color,
          text_color: workspace.text_color,
          parent_category: workspace,
          user: user,
        )

      channel.description = description if description.present?
      channel.set_permissions(channel_permissions(channel_group))

      channel.custom_fields[WORKSPACE_ENABLED] = true
      channel.custom_fields[WORKSPACE_KIND] = WORKSPACE_KIND_CHANNEL
      channel.custom_fields[WORKSPACE_PARENT_CATEGORY_ID] = workspace.id
      channel.custom_fields[WORKSPACE_GROUP_ID] = channel_group.id
      channel.custom_fields[WORKSPACE_VISIBILITY] = visibility
      channel.custom_fields[WORKSPACE_CHANNEL_MODE] = channel_mode
      channel.save!
      assign_final_category_slug!(channel)

      channel_group.custom_fields["workspace_category_id"] = channel.id
      channel_group.custom_fields["workspace_kind"] = WORKSPACE_KIND_CHANNEL
      channel_group.custom_fields["workspace_parent_group_id"] = workspace_group.id
      channel_group.save!

      configure_category_notification_default(channel_group, channel)
      DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: channel, user: user).call

      channel
    end

    private

    def validate!
      raise Discourse::InvalidAccess if user.blank?
      raise Discourse::InvalidAccess if !workspace&.workspace_root?
      raise Discourse::InvalidParameters.new(:name) if name.blank?
      raise Discourse::InvalidParameters.new(:visibility) if !valid_visibility?
      raise Discourse::InvalidParameters.new(:channel_mode) if !valid_channel_mode?

      return if user.admin?
      return if DiscourseWorkspaceGroups.can_manage_workspace?(workspace, user)

      raise Discourse::InvalidAccess if !workspace.workspace_group.users.exists?(id: user.id)
      raise Discourse::InvalidAccess if !workspace.workspace_members_can_create_channels?
      raise Discourse::InvalidAccess if visibility == VISIBILITY_PRIVATE && !workspace.workspace_members_can_create_private_channels?
    end

    def valid_visibility?
      [VISIBILITY_PUBLIC, VISIBILITY_PRIVATE].include?(visibility)
    end

    def valid_channel_mode?
      DiscourseWorkspaceGroups.valid_channel_mode?(channel_mode)
    end

    def ensure_channel_group
      group_name = DiscourseWorkspaceGroups.channel_group_name(workspace, name)
      existing_group = Group.find_by(name: group_name)
      if existing_group.present?
        raise Discourse::InvalidParameters.new(collision_error) if existing_group.full_name == name

        group_name = DiscourseWorkspaceGroups.disambiguated_channel_group_name(workspace, name)
        existing_group = Group.find_by(name: group_name)
        raise Discourse::InvalidParameters.new(collision_error) if existing_group.present?
      end

      group =
        Group.create!(
          name: group_name,
          full_name: name,
          visibility_level: Group.visibility_levels[:members],
          members_visibility_level: Group.visibility_levels[:members],
          mentionable_level: Group::ALIAS_LEVELS[:nobody],
          messageable_level: Group::ALIAS_LEVELS[:nobody],
        )

      group.update!(name: group_name, full_name: name)
      ensure_group_membership(group, user, owner: true)

      group
    end

    def ensure_group_membership(group, member, owner: false)
      group.add(member) if !group.users.exists?(id: member.id)
      return if !owner

      group.group_users.find_by!(user_id: member.id).update!(owner: true)
      DiscourseWorkspaceGroups.promote_workspace_owner!(group, member)
    end

    def root_permissions(workspace_group, new_group_id = nil)
      group_ids = DiscourseWorkspaceGroups.workspace_channel_group_ids(workspace)
      group_ids << new_group_id if new_group_id.present?

      DiscourseWorkspaceGroups.workspace_root_permissions(
        workspace_group,
        group_ids,
        public_read: workspace.workspace_root_public_read?,
      )
    end

    def channel_permissions(channel_group)
      DiscourseWorkspaceGroups.channel_permissions(channel_group, channel_mode)
    end

    def configure_category_notification_default(channel_group, channel)
      notification_level = NotificationLevels.all[:watching_first_post]
      GroupCategoryNotificationDefault.create!(
        group: channel_group,
        category: channel,
        notification_level: notification_level,
      )
      CategoryUser.set_notification_level_for_category(user, notification_level, channel.id)
    end

    def collision_error
      I18n.t("discourse_workspace_groups.errors.channel_name_collision", name: name)
    end

    def temporary_category_slug
      "#{TEMPORARY_CATEGORY_SLUG_PREFIX}-#{SecureRandom.hex(16)}"
    end

    def assign_final_category_slug!(channel)
      CATEGORY_SLUG_COLLISION_ATTEMPTS.times do |attempt|
        return if channel.update(slug: category_slug(channel, attempt: attempt))

        if !slug_collision?(channel)
          raise Discourse::InvalidParameters.new(channel.errors.attribute_names.first || :category)
        end
      end

      raise Discourse::InvalidParameters.new(collision_error)
    end

    def category_slug(channel, attempt:)
      base_slug = Slug.for(name, "").presence || "channel"
      workspace_slug = Slug.for(workspace.slug, "").presence || "workspace"
      scoped_base = "#{workspace_slug}-#{base_slug}"
      suffix = "-#{channel.id}"
      suffix = "#{suffix}-#{attempt + 1}" if attempt.positive?

      "#{scoped_base.first(255 - suffix.length)}#{suffix}"
    end

    def slug_collision?(channel)
      channel.errors.attribute_names.include?(:slug)
    end
  end
end
