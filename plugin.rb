# frozen_string_literal: true

# name: discourse-workspace-groups
# about: Prototypes workspace and channel behavior on top of Discourse categories and groups.
# version: 0.1
# authors: Anton Akhmerov
# url: https://github.com/discourse/discourse
# license: GPL-2.0-only
# copyright: Copyright (C) 2026 Anton Akhmerov

enabled_site_setting :discourse_workspace_groups_enabled

register_asset "stylesheets/common/discourse-workspace-groups.scss"
register_svg_icon "layer-group"
register_svg_icon "lock"
register_svg_icon "table-cells-large"

module ::DiscourseWorkspaceGroups
  PLUGIN_NAME = "discourse-workspace-groups"
  MAX_GROUP_NAME_LENGTH = 20

  WORKSPACE_ENABLED = "workspace_enabled"
  WORKSPACE_KIND = "workspace_kind"
  WORKSPACE_GROUP_ID = "workspace_group_id"
  WORKSPACE_PARENT_CATEGORY_ID = "workspace_parent_category_id"
  WORKSPACE_VISIBILITY = "workspace_visibility"
  WORKSPACE_ARCHIVED = "workspace_archived"
  WORKSPACE_ROOT_PUBLIC_READ = "workspace_root_public_read"

  WORKSPACE_KIND_ROOT = "workspace"
  WORKSPACE_KIND_CHANNEL = "channel"

  VISIBILITY_PUBLIC = "public"
  VISIBILITY_PRIVATE = "private"
  ROOT_CHANNEL_PERMISSION = :readonly

  def self.positive_custom_field_id(value)
    integer = value.to_i
    integer > 0 ? integer : nil
  end

  def self.excluded_top_level_category_ids
    SiteSetting.discourse_workspace_groups_excluded_top_level_category_ids
      .split("|")
      .filter_map { |value| positive_custom_field_id(value) }
  end

  def self.workspace_candidate?(category)
    category.present? &&
      category.parent_category_id.blank? &&
      !category.subcategories.exists? &&
      !category.workspace_root? &&
      !excluded_top_level_category_ids.include?(category.id)
  end

  def self.workspace_group_name(category)
    descriptive_group_name("team", category.slug.presence || category.name, category.id)
  end

  def self.channel_group_name(workspace, name)
    descriptive_group_name("chan", name, workspace.id)
  end

  def self.descriptive_group_name(prefix, label, suffix)
    suffix = suffix.to_s
    available_slug_length = MAX_GROUP_NAME_LENGTH - prefix.length - suffix.length - 2
    slug = Slug.for(label.to_s, "", available_slug_length).presence || "group"

    [prefix, slug, suffix].join("-")
  end

  def self.group_member?(group, user)
    return false if group.blank? || user.blank?

    group.group_users.where(user_id: user.id).exists?
  end

  def self.group_owner?(group, user)
    return false if group.blank? || user.blank?

    group.group_users.where(user_id: user.id, owner: true).exists?
  end

  def self.last_group_owner?(group, user)
    return false if !group_owner?(group, user)

    !group.group_users.where(owner: true).where.not(user_id: user.id).exists?
  end

  def self.can_leave_channel_group?(group, user)
    return false if !group_member?(group, user)
    return false if last_group_owner?(group, user)

    true
  end

  def self.can_remove_channel_group_member?(group, target_user)
    return false if !group_member?(group, target_user)
    return false if last_group_owner?(group, target_user)

    true
  end

  def self.can_manage_workspace_channel?(category, user)
    return false if user.blank? || category.blank? || !category.workspace_channel?
    return true if user.admin?

    group_owner?(category.workspace_group, user)
  end

  def self.workspace_channel_category_for_group(group)
    return if group.blank?
    return if group.custom_fields["workspace_kind"] != WORKSPACE_KIND_CHANNEL

    category_id = positive_custom_field_id(group.custom_fields["workspace_category_id"])
    return if category_id.blank?

    category = Category.find_by(id: category_id)
    return if category.blank? || !category.workspace_channel? || category.workspace_group_id != group.id

    category
  end

  def self.workspace_channel_group_ids(workspace)
    channels = Category.where(parent_category_id: workspace.id).to_a
    Category.preload_custom_fields(
      channels,
      [WORKSPACE_ENABLED, WORKSPACE_KIND, WORKSPACE_GROUP_ID],
    )

    channels.select(&:workspace_channel?).map(&:workspace_group_id).compact.uniq
  end

  def self.workspace_root_permissions(workspace_group, channel_group_ids, public_read: false)
    permissions = { workspace_group.id => :full }
    permissions[:everyone] = :readonly if public_read
    channel_group_ids.each { |group_id| permissions[group_id] = ROOT_CHANNEL_PERMISSION }
    permissions
  end

  def self.sync_workspace_root_permissions!(workspace)
    return workspace if workspace.blank? || !workspace.workspace_root?

    workspace_group = workspace.workspace_group
    return workspace if workspace_group.blank?

    desired_permissions =
      workspace_root_permissions(
        workspace_group,
        workspace_channel_group_ids(workspace),
        public_read: workspace.workspace_root_public_read?,
      )
    desired_permission_types =
      desired_permissions.transform_values { |permission| CategoryGroup.permission_types.fetch(permission) }
    current_permission_types = workspace.category_groups.pluck(:group_id, :permission_type).to_h

    return workspace if current_permission_types == desired_permission_types

    workspace.set_permissions(desired_permissions)
    workspace.save!
    workspace
  end

  def self.archived_workspace_category?(category)
    category&.workspace_channel? && category.workspace_archived?
  end

  def self.archived_workspace_topic?(topic)
    archived_workspace_category?(topic&.category)
  end
end

require_relative "lib/discourse_workspace_groups/engine"
require_relative "lib/discourse_workspace_groups/ensure_workspace"
require_relative "lib/discourse_workspace_groups/create_channel"
require_relative "lib/discourse_workspace_groups/join_channel"
require_relative "lib/discourse_workspace_groups/leave_channel"
require_relative "lib/discourse_workspace_groups/add_channel_members"
require_relative "lib/discourse_workspace_groups/remove_channel_member"
require_relative "lib/discourse_workspace_groups/set_channel_archive_state"
require_relative "lib/discourse_workspace_groups/sync_category_chat_channel"
require_relative "lib/discourse_workspace_groups/sync_channel_group_chat_membership"

after_initialize do
  module ::DiscourseWorkspaceGroups::GuardianArchiveRestrictions
    def can_create_topic_on_category?(category)
      category = category.is_a?(Category) ? category : Category.find_by(id: category)
      return false if DiscourseWorkspaceGroups.archived_workspace_category?(category)

      super
    end

    def can_create_post?(topic)
      return false if DiscourseWorkspaceGroups.archived_workspace_topic?(topic)

      super
    end

    def can_create_post_on_topic?(topic)
      return false if DiscourseWorkspaceGroups.archived_workspace_topic?(topic)

      super
    end

    def can_edit_topic?(topic)
      return false if DiscourseWorkspaceGroups.archived_workspace_topic?(topic)

      super
    end

    def can_delete_topic?(topic)
      return false if DiscourseWorkspaceGroups.archived_workspace_topic?(topic)

      super
    end

    def can_edit_post?(post)
      return false if DiscourseWorkspaceGroups.archived_workspace_topic?(post&.topic)

      super
    end

    def can_delete_post?(post)
      return false if DiscourseWorkspaceGroups.archived_workspace_topic?(post&.topic)

      super
    end
  end

  Guardian.prepend(::DiscourseWorkspaceGroups::GuardianArchiveRestrictions)

  Discourse::Application.routes.prepend do
    get "c/*category_slug_path/:category_id/overview" =>
          "discourse_workspace_groups/workspaces#overview_page",
        format: false
  end

  Discourse::Application.routes.append do
    mount ::DiscourseWorkspaceGroups::Engine, at: "/workspace-groups"
  end

  require_relative "app/controllers/discourse_workspace_groups/workspaces_controller"

  register_category_custom_field_type(DiscourseWorkspaceGroups::WORKSPACE_ENABLED, :boolean)
  register_category_custom_field_type(DiscourseWorkspaceGroups::WORKSPACE_KIND, :string)
  register_category_custom_field_type(DiscourseWorkspaceGroups::WORKSPACE_GROUP_ID, :integer)
  register_category_custom_field_type(
    DiscourseWorkspaceGroups::WORKSPACE_PARENT_CATEGORY_ID,
    :integer,
  )
  register_category_custom_field_type(DiscourseWorkspaceGroups::WORKSPACE_VISIBILITY, :string)
  register_category_custom_field_type(DiscourseWorkspaceGroups::WORKSPACE_ARCHIVED, :boolean)
  register_category_custom_field_type(
    DiscourseWorkspaceGroups::WORKSPACE_ROOT_PUBLIC_READ,
    :boolean,
  )

  register_group_custom_field_type("workspace_category_id", :integer)
  register_group_custom_field_type("workspace_kind", :string)
  register_group_custom_field_type("workspace_parent_group_id", :integer)

  register_preloaded_category_custom_fields(DiscourseWorkspaceGroups::WORKSPACE_ENABLED)
  register_preloaded_category_custom_fields(DiscourseWorkspaceGroups::WORKSPACE_KIND)
  register_preloaded_category_custom_fields(DiscourseWorkspaceGroups::WORKSPACE_GROUP_ID)
  register_preloaded_category_custom_fields(
    DiscourseWorkspaceGroups::WORKSPACE_PARENT_CATEGORY_ID,
  )
  register_preloaded_category_custom_fields(DiscourseWorkspaceGroups::WORKSPACE_VISIBILITY)
  register_preloaded_category_custom_fields(DiscourseWorkspaceGroups::WORKSPACE_ARCHIVED)
  register_preloaded_category_custom_fields(DiscourseWorkspaceGroups::WORKSPACE_ROOT_PUBLIC_READ)

  add_to_class(:category, :workspace_enabled?) do
    custom_fields[DiscourseWorkspaceGroups::WORKSPACE_ENABLED].to_s == "true"
  end

  add_to_class(:category, :workspace_kind) do
    custom_fields[DiscourseWorkspaceGroups::WORKSPACE_KIND]
  end

  add_to_class(:category, :workspace_root?) do
    workspace_enabled? && workspace_kind == DiscourseWorkspaceGroups::WORKSPACE_KIND_ROOT
  end

  add_to_class(:category, :workspace_channel?) do
    workspace_enabled? && workspace_kind == DiscourseWorkspaceGroups::WORKSPACE_KIND_CHANNEL
  end

  add_to_class(:category, :workspace_group_id) do
    DiscourseWorkspaceGroups.positive_custom_field_id(
      custom_fields[DiscourseWorkspaceGroups::WORKSPACE_GROUP_ID],
    )
  end

  add_to_class(:category, :workspace_group) do
    Group.find_by(id: workspace_group_id)
  end

  add_to_class(:category, :workspace_parent_category_id) do
    DiscourseWorkspaceGroups.positive_custom_field_id(
      custom_fields[DiscourseWorkspaceGroups::WORKSPACE_PARENT_CATEGORY_ID],
    )
  end

  add_to_class(:category, :workspace_parent_category) do
    return parent_category if workspace_root?
    return Category.find_by(id: workspace_parent_category_id) if workspace_parent_category_id

    parent_category
  end

  add_to_class(:category, :workspace_visibility) do
    custom_fields[DiscourseWorkspaceGroups::WORKSPACE_VISIBILITY]
  end

  add_to_class(:category, :workspace_archived?) do
    custom_fields[DiscourseWorkspaceGroups::WORKSPACE_ARCHIVED].to_s == "true"
  end

  add_to_class(:category, :workspace_root_public_read?) do
    custom_fields[DiscourseWorkspaceGroups::WORKSPACE_ROOT_PUBLIC_READ].to_s == "true"
  end

  add_to_class(Guardian, :can_enable_workspace_group?) do |category|
    user&.admin? && DiscourseWorkspaceGroups.workspace_candidate?(category)
  end

  add_to_class(Guardian, :can_create_workspace_channel?) do |category|
    return false if user.blank? || category.blank?
    return true if is_admin?

    workspace = category.workspace_root? ? category : category.workspace_parent_category
    return false if !workspace&.workspace_root?
    return false if !SiteSetting.discourse_workspace_groups_members_can_create_channels

    group = workspace.workspace_group
    group.present? && group.users.where(id: user.id).exists?
  end

  add_to_class(Guardian, :can_join_workspace_channel?) do |category|
    return false if user.blank? || category.blank? || !category.workspace_channel?

    workspace = category.workspace_parent_category
    return false if !workspace&.workspace_root?
    return false if category.workspace_visibility != DiscourseWorkspaceGroups::VISIBILITY_PUBLIC
    return false if category.workspace_group.blank?
    return false if category.workspace_group.users.exists?(id: user.id)

    is_admin? || workspace.workspace_group&.users&.where(id: user.id)&.exists?
  end

  add_to_class(Guardian, :can_leave_workspace_channel?) do |category|
    return false if user.blank? || category.blank? || !category.workspace_channel?
    return false if category.workspace_group.blank?

    DiscourseWorkspaceGroups.can_leave_channel_group?(category.workspace_group, user)
  end

  add_to_class(Guardian, :can_manage_workspace_channel?) do |category|
    DiscourseWorkspaceGroups.can_manage_workspace_channel?(category, user)
  end

  add_to_serializer(:basic_category, :workspace_enabled) { object.workspace_enabled? }
  add_to_serializer(:basic_category, :workspace_kind) { object.workspace_kind }
  add_to_serializer(:basic_category, :workspace_group_id) { object.workspace_group_id }
  add_to_serializer(:basic_category, :workspace_parent_category_id) do
    object.workspace_parent_category_id
  end
  add_to_serializer(:basic_category, :workspace_visibility) { object.workspace_visibility }
  add_to_serializer(:basic_category, :workspace_archived) { object.workspace_archived? }
  add_to_serializer(:basic_category, :workspace_root_public_read) do
    object.workspace_root_public_read?
  end
  add_to_serializer(:basic_category, :workspace_can_create_channel) do
    scope&.can_create_workspace_channel?(object)
  end
  add_to_serializer(:basic_category, :workspace_can_enable) do
    scope&.can_enable_workspace_group?(object)
  end

  on(:user_added_to_group) do |user, group|
    DiscourseWorkspaceGroups::SyncChannelGroupChatMembership.new(user: user, group: group).call
  end

  on(:category_updated) do |category|
    next if !category.is_a?(Category) || !category.workspace_channel?

    DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: category).call
  end
end
