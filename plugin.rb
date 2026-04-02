# frozen_string_literal: true

# name: discourse-workspace-groups
# about: Prototypes workspace and channel behavior on top of Discourse categories and groups.
# version: 0.1
# authors: Anton Akhmerov
# url: https://github.com/discourse/discourse
# license: GPL-2.0-only
# copyright: Copyright (C) 2026 Anton Akhmerov

require "digest/sha1"

enabled_site_setting :discourse_workspace_groups_enabled

register_asset "stylesheets/common/discourse-workspace-groups.scss"
register_svg_icon "layer-group"
register_svg_icon "lock"

module ::DiscourseWorkspaceGroups
  PLUGIN_NAME = "discourse-workspace-groups"

  WORKSPACE_ENABLED = "workspace_enabled"
  WORKSPACE_KIND = "workspace_kind"
  WORKSPACE_GROUP_ID = "workspace_group_id"
  WORKSPACE_PARENT_CATEGORY_ID = "workspace_parent_category_id"
  WORKSPACE_VISIBILITY = "workspace_visibility"

  WORKSPACE_KIND_ROOT = "workspace"
  WORKSPACE_KIND_CHANNEL = "channel"

  VISIBILITY_PUBLIC = "public"
  VISIBILITY_PRIVATE = "private"

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
    slug = Slug.for(category.slug.presence || category.name, "")[0, 6]
    digest = Digest::SHA1.hexdigest("#{category.id}-#{category.name}")[0, 6]
    "wg-#{category.id}-#{slug}-#{digest}"[0, 20]
  end

  def self.channel_group_name(workspace, name)
    slug = Slug.for(name, "")[0, 5]
    digest = Digest::SHA1.hexdigest("#{workspace.id}-#{name}")[0, 6]
    "wc-#{workspace.id}-#{slug}-#{digest}"[0, 20]
  end
end

require_relative "lib/discourse_workspace_groups/engine"
require_relative "lib/discourse_workspace_groups/ensure_workspace"
require_relative "lib/discourse_workspace_groups/create_channel"
require_relative "lib/discourse_workspace_groups/sync_category_chat_channel"

after_initialize do
  Discourse::Application.routes.append do
    mount ::DiscourseWorkspaceGroups::Engine, at: "/workspace-groups"
    get "c/*category_slug_path_with_id/overview" => "list#category_default",
        constraints: {
          format: "html",
        }
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

  add_to_serializer(:basic_category, :workspace_enabled) { object.workspace_enabled? }
  add_to_serializer(:basic_category, :workspace_kind) { object.workspace_kind }
  add_to_serializer(:basic_category, :workspace_group_id) { object.workspace_group_id }
  add_to_serializer(:basic_category, :workspace_parent_category_id) do
    object.workspace_parent_category_id
  end
  add_to_serializer(:basic_category, :workspace_visibility) { object.workspace_visibility }
  add_to_serializer(:basic_category, :workspace_can_create_channel) do
    scope&.can_create_workspace_channel?(object)
  end
  add_to_serializer(:basic_category, :workspace_can_enable) do
    scope&.can_enable_workspace_group?(object)
  end

  on(:category_updated) do |category|
    next if !category.is_a?(Category) || !category.workspace_channel?

    DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: category).call
  end
end
