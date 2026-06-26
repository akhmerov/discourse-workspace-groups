# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class UpdateWorkspace
    UNSET = Object.new.freeze

    attr_reader :workspace,
                :user,
                :description,
                :color,
                :public_read,
                :members_can_create_channels,
                :members_can_create_private_channels,
                :auto_join_channel_ids

    def initialize(
      workspace:,
      user:,
      description:,
      color: UNSET,
      public_read:,
      members_can_create_channels:,
      members_can_create_private_channels:,
      auto_join_channel_ids: nil
    )
      @workspace = workspace
      @user = user
      @description = description.to_s.strip
      @color = color == UNSET ? workspace.color : normalize_color(color)
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
      @auto_join_channel_ids_submitted = !auto_join_channel_ids.nil?
      @auto_join_channel_ids =
        normalize_channel_ids(auto_join_channel_ids, workspace.workspace_auto_join_channel_ids)
    end

    def call
      validate!
      previous_color = workspace.color
      previous_auto_join_channel_ids = workspace.workspace_auto_join_channel_ids

      Category.transaction do
        update_color!
        sync_inherited_channel_colors!(previous_color)
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
      raise Discourse::InvalidParameters.new(:color) if !valid_color?
      raise Discourse::InvalidParameters.new(:auto_join_channel_ids) if !valid_auto_join_channel_ids?
    end

    def update_color!
      return if workspace.color == color

      workspace.update!(color: color)
    end

    def sync_inherited_channel_colors!(previous_color)
      return if previous_color == color

      workspace_channel_ids =
        CategoryCustomField.where(
          name: WORKSPACE_KIND,
          value: WORKSPACE_KIND_CHANNEL,
        ).select(:category_id)

      Category
        .where(id: workspace_channel_ids, parent_category_id: workspace.id, color: previous_color)
        .update_all(color: color, updated_at: Time.zone.now)
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
      workspace.custom_fields[WORKSPACE_AUTO_JOIN_CHANNEL_IDS] = auto_join_channel_ids_to_save
      workspace.save_custom_fields(true)

      DiscourseWorkspaceGroups.sync_workspace_root_permissions!(workspace)
    end

    def sync_new_auto_join_memberships!(previous_auto_join_channel_ids)
      newly_added_channel_ids =
        auto_join_channel_ids_to_save - Array.wrap(previous_auto_join_channel_ids)
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

    def normalize_color(value)
      value.to_s.delete_prefix("#").upcase
    end

    def valid_color?
      color.present? && color.match?(/\A\h{6}\z/)
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
      return true if !@auto_join_channel_ids_submitted || auto_join_channel_ids.blank?

      submitted_configurable_ids =
        configurable_auto_join_channels(auto_join_channel_ids).map(&:id)
      invalid_ids =
        auto_join_channel_ids - submitted_configurable_ids - preserved_auto_join_channel_ids
      invalid_ids.blank?
    end

    def auto_join_channel_ids_to_save
      return auto_join_channel_ids if !@auto_join_channel_ids_submitted

      (preserved_auto_join_channel_ids + auto_join_channel_ids).uniq
    end

    def preserved_auto_join_channel_ids
      @preserved_auto_join_channel_ids ||=
        DiscourseWorkspaceGroups.workspace_auto_join_channels(workspace)
          .reject do |channel|
            DiscourseWorkspaceGroups.can_manage_workspace_auto_join_channel?(channel, user)
          end
          .map(&:id)
    end

    def configurable_auto_join_channels(channel_ids)
      Category
        .where(id: channel_ids, parent_category_id: workspace.id)
        .to_a
        .tap do |categories|
          Category.preload_custom_fields(categories, Site.preloaded_category_custom_fields)
        end
        .select do |channel|
          DiscourseWorkspaceGroups.can_manage_workspace_auto_join_channel?(channel, user)
        end
        .reject(&:workspace_archived?)
    end
  end
end
