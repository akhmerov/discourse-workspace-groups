# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class CreateChannel
    attr_reader :workspace, :user, :name, :description, :visibility

    def initialize(workspace:, user:, name:, description:, visibility:)
      @workspace = workspace
      @user = user
      @name = name.to_s.strip
      @description = description.to_s.strip
      @visibility = visibility.presence || VISIBILITY_PUBLIC
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
          slug: Slug.for(name, ""),
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
      channel.save!

      channel_group.custom_fields["workspace_category_id"] = channel.id
      channel_group.custom_fields["workspace_kind"] = WORKSPACE_KIND_CHANNEL
      channel_group.custom_fields["workspace_parent_group_id"] = workspace_group.id
      channel_group.save!

      DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: channel, user: user).call

      channel
    end

    private

    def validate!
      raise Discourse::InvalidAccess if user.blank?
      raise Discourse::InvalidAccess if !workspace&.workspace_root?
      raise Discourse::InvalidParameters.new(:name) if name.blank?
      raise Discourse::InvalidParameters.new(:visibility) if !valid_visibility?

      return if user.admin?
      raise Discourse::InvalidAccess if !workspace.workspace_group.users.exists?(id: user.id)
      raise Discourse::InvalidAccess if !SiteSetting.discourse_workspace_groups_members_can_create_channels
    end

    def valid_visibility?
      [VISIBILITY_PUBLIC, VISIBILITY_PRIVATE].include?(visibility)
    end

    def ensure_channel_group
      group_name = DiscourseWorkspaceGroups.channel_group_name(workspace, name)
      existing_group = Group.find_by(name: group_name)
      raise Discourse::InvalidParameters.new(collision_error) if existing_group.present?

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
      group.group_users.where(user_id: member.id).update_all(owner: true) if owner
    end

    def root_permissions(workspace_group, new_group_id = nil)
      group_ids = DiscourseWorkspaceGroups.workspace_channel_group_ids(workspace)
      group_ids << new_group_id if new_group_id.present?

      DiscourseWorkspaceGroups.workspace_root_permissions(workspace_group, group_ids)
    end

    def channel_permissions(channel_group)
      { channel_group.id => :full }
    end

    def collision_error
      I18n.t("discourse_workspace_groups.errors.channel_name_collision", name: name)
    end
  end
end
