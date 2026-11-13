# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class EnsureWorkspace
    attr_reader :category,
                :user,
                :public_read,
                :members_can_create_channels,
                :members_can_create_private_channels,
                :create_starter_channel

    def initialize(
      category:,
      user:,
      public_read: false,
      members_can_create_channels: SiteSetting.discourse_workspace_groups_members_can_create_channels,
      members_can_create_private_channels: members_can_create_channels,
      create_starter_channel: false
    )
      @category = category
      @user = user
      @public_read = public_read
      @members_can_create_channels = members_can_create_channels
      @members_can_create_private_channels = members_can_create_private_channels
      @create_starter_channel = create_starter_channel
    end

    def call
      raise Discourse::InvalidParameters.new(:category_id) if category.blank?
      raise Discourse::InvalidAccess if category.parent_category_id.present?
      raise Discourse::InvalidParameters.new(:subcategories) if category.subcategories.exists?

      ActiveRecord::Base.transaction do
        enable_workspace!
        add_starter_channel! if create_starter_channel
      end

      category
    end

    private

    def enable_workspace!
      workspace_group = ensure_workspace_group

      category.custom_fields[WORKSPACE_ENABLED] = true
      category.custom_fields[WORKSPACE_KIND] = WORKSPACE_KIND_ROOT
      category.custom_fields[WORKSPACE_GROUP_ID] = workspace_group.id
      category.custom_fields[WORKSPACE_ROOT_PUBLIC_READ] = public_read
      category.custom_fields[WORKSPACE_MEMBERS_CAN_CREATE_CHANNELS] = members_can_create_channels
      category.custom_fields[WORKSPACE_MEMBERS_CAN_CREATE_PRIVATE_CHANNELS] =
        members_can_create_channels && members_can_create_private_channels
      category.set_permissions(root_permissions(workspace_group))
      category.save!
    end

    # Start a team with one public channel that every member joins, so the team
    # opens on a usable conversation instead of an empty channel list.
    def add_starter_channel!
      return if user.blank?

      channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: category,
          user: user,
          name: I18n.t("discourse_workspace_groups.starter_channel.name"),
          description: I18n.t("discourse_workspace_groups.starter_channel.description"),
          visibility: VISIBILITY_PUBLIC,
        ).call

      category.custom_fields[WORKSPACE_AUTO_JOIN_CHANNEL_IDS] = [channel.id]
      category.save_custom_fields(true)
    end

    def ensure_workspace_group
      group = category.workspace_group
      group_name = DiscourseWorkspaceGroups.workspace_group_name(category)

      if group.blank?
        group =
          Group.find_by(name: group_name) ||
            Group.create!(
              name: group_name,
              full_name: category.name,
              visibility_level: Group.visibility_levels[:members],
              members_visibility_level: Group.visibility_levels[:members],
              mentionable_level: Group::ALIAS_LEVELS[:nobody],
              messageable_level: Group::ALIAS_LEVELS[:nobody],
            )
      end

      group.update!(name: group_name, full_name: category.name)

      group.custom_fields["workspace_category_id"] = category.id
      group.custom_fields["workspace_kind"] = WORKSPACE_KIND_ROOT
      group.save!

      ensure_group_owner(group, user)
      group
    end

    def ensure_group_owner(group, owner)
      return if owner.blank?

      group.add(owner) if !group.users.exists?(id: owner.id)
      group.group_users.find_by!(user_id: owner.id).update!(owner: true)
      DiscourseWorkspaceGroups.promote_workspace_owner!(group, owner)
    end

    def root_permissions(workspace_group)
      DiscourseWorkspaceGroups.workspace_root_permissions(
        workspace_group,
        DiscourseWorkspaceGroups.workspace_channel_group_ids(category),
        public_read: public_read,
      )
    end
  end
end
