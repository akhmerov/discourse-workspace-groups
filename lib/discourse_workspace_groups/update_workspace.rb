# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class UpdateWorkspace
    attr_reader :workspace,
                :user,
                :description,
                :public_read,
                :members_can_create_channels,
                :members_can_create_private_channels,
                :auto_join_channel_ids

    def initialize(
      workspace:,
      user:,
      description:,
      public_read:,
      members_can_create_channels:,
      members_can_create_private_channels:,
      auto_join_channel_ids: nil
    )
      @workspace = workspace
      @user = user
      @description = description.to_s.strip
      @public_read = cast_boolean(public_read, workspace.workspace_root_public_read?)
      @members_can_create_channels =
        cast_boolean(
          members_can_create_channels,
          workspace.workspace_members_can_create_channels?,
        )
      @members_can_create_private_channels =
        cast_boolean(
          members_can_create_private_channels,
          workspace.workspace_members_can_create_private_channels?,
        )
      @auto_join_channel_ids =
        normalize_channel_ids(auto_join_channel_ids, workspace.workspace_auto_join_channel_ids)
    end

    def call
      validate!
      previous_auto_join_channel_ids = workspace.workspace_auto_join_channel_ids

      Category.transaction do
        update_description!
        update_permissions!
        sync_new_auto_join_memberships!(previous_auto_join_channel_ids)
      end

      workspace.reload
    end

    private

    def validate!
      raise Discourse::InvalidAccess if user.blank?
      raise Discourse::InvalidAccess if !workspace&.workspace_root?
      raise Discourse::InvalidAccess if !DiscourseWorkspaceGroups.can_manage_workspace?(workspace, user)
      raise Discourse::InvalidParameters.new(:auto_join_channel_ids) if !valid_auto_join_channel_ids?
    end

    def update_description!
      return if current_description == description

      first_post = workspace.topic&.first_post
      if first_post.blank?
        return if description.blank?

        workspace.update_column(:description, description)
        workspace.create_category_definition
        return
      end

      first_post.revise(user, { raw: description }, skip_validations: true)
      first_post.reload
      workspace.update_column(:description, first_post.cooked.presence)
    end

    def update_permissions!
      workspace.custom_fields[WORKSPACE_ROOT_PUBLIC_READ] = public_read
      workspace.custom_fields[WORKSPACE_MEMBERS_CAN_CREATE_CHANNELS] = members_can_create_channels
      workspace.custom_fields[WORKSPACE_MEMBERS_CAN_CREATE_PRIVATE_CHANNELS] =
        members_can_create_channels && members_can_create_private_channels
      workspace.custom_fields[WORKSPACE_AUTO_JOIN_CHANNEL_IDS] = auto_join_channel_ids
      workspace.save_custom_fields(true)

      DiscourseWorkspaceGroups.sync_workspace_root_permissions!(workspace)
    end

    def sync_new_auto_join_memberships!(previous_auto_join_channel_ids)
      newly_added_channel_ids = auto_join_channel_ids - Array.wrap(previous_auto_join_channel_ids)
      return if newly_added_channel_ids.blank?

      workspace_group = workspace.workspace_group
      return if workspace_group.blank?

      DiscourseWorkspaceGroups.sync_workspace_auto_join_memberships!(
        workspace,
        users: workspace_group.users.to_a,
        channel_ids: newly_added_channel_ids,
      )
    end

    def current_description
      workspace.topic&.first_post&.raw.to_s.strip
    end

    def cast_boolean(value, fallback)
      return fallback if value.nil?

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def normalize_channel_ids(value, fallback)
      return Array.wrap(fallback) if value.nil?

      DiscourseWorkspaceGroups.normalize_custom_field_id_list(value)
    end

    def valid_auto_join_channel_ids?
      return true if auto_join_channel_ids.blank?

      channels =
        Category.where(id: auto_join_channel_ids, parent_category_id: workspace.id).to_a.tap do |categories|
          Category.preload_custom_fields(categories, Site.preloaded_category_custom_fields)
        end

      auto_join_channel_ids.sort ==
        channels.select(&:workspace_channel?).reject(&:workspace_archived?).map(&:id).sort
    end
  end
end
