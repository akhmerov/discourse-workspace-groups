# frozen_string_literal: true

require "set"

module ::DiscourseWorkspaceGroups
  class WorkspacesController < ::ApplicationController
    requires_login

    before_action :ensure_plugin_enabled
    before_action :find_workspace, except: :overview_page
    before_action :find_overview_workspace, only: :overview_page

    def overview_page
      guardian.ensure_can_see!(@workspace)
      raise Discourse::NotFound if !@workspace.workspace_root?

      @title = I18n.t("js.discourse_workspace_groups.overview_title", name: @workspace.name)
      @full_title = "#{@title} - #{SiteSetting.title}"
      @description_meta = @workspace.description_text.presence || @title

      render "discourse_workspace_groups/workspaces/overview_page"
    end

    def show
      guardian.ensure_can_see!(@workspace)
      raise Discourse::NotFound if !@workspace.workspace_root?

      active_channels = workspace_channels(archived: false)
      archived_channels = workspace_channels(archived: true)
      context = build_channels_context(active_channels + archived_channels)
      visible_active_channels = visible_channels(active_channels, **context)
      visible_archived_channels = visible_channels(archived_channels, **context)

      render json: {
               workspace: serialize_workspace(**context, all_active_channels: active_channels),
               archived_channel_count: visible_archived_channels.length,
               channels: visible_active_channels.map { |category| serialize_channel(category, **context) },
             }
    end

    def archived_channels
      guardian.ensure_can_see!(@workspace)
      raise Discourse::NotFound if !@workspace.workspace_root?

      archived_channels = workspace_channels(archived: true)
      context = build_channels_context(archived_channels)

      render json: {
               channels:
                 visible_channels(archived_channels, **context).map do |category|
                   serialize_channel(category, **context)
                 end,
             }
    end

    def enable
      guardian.ensure_can_see!(@workspace)
      raise Discourse::InvalidAccess if !guardian.can_enable_workspace_group?(@workspace)

      category = ::DiscourseWorkspaceGroups::EnsureWorkspace.new(
        category: @workspace,
        user: current_user,
      ).call

      render json: { category_id: category.id, category_url: category.url }
    end

    def create_channel
      guardian.ensure_can_see!(@workspace)
      raise Discourse::InvalidAccess if !guardian.can_create_workspace_channel?(@workspace)

      category = ::DiscourseWorkspaceGroups::CreateChannel.new(
        workspace: @workspace,
        user: current_user,
        name: params.require(:name),
        description: params[:description],
        visibility: params[:visibility],
        channel_mode: params[:channel_mode],
      ).call
      category = Category.find(category.id)
      Category.preload_custom_fields([category], Site.preloaded_category_custom_fields)

      context = build_channels_context([category])

      render json: {
               category_id: category.id,
               category_url: category.url,
               workspace_id: @workspace.id,
               visibility: category.workspace_visibility,
               channel: serialize_channel(category, **context),
             }
    end

    def update_sidebar_channels
      guardian.ensure_can_see!(@workspace)
      raise Discourse::NotFound if !@workspace.workspace_root?

      ordered_ids = Array(params.require(:channel_ids)).map(&:to_i)
      active_channels = workspace_channels(archived: false)
      context = build_channels_context(active_channels)
      visible_channel_ids = visible_channels(active_channels, **context).map(&:id).to_set

      if ordered_ids.uniq.length != ordered_ids.length || ordered_ids.any? { |id| !visible_channel_ids.include?(id) }
        raise Discourse::InvalidParameters.new(:channel_ids)
      end

      sidebar_orders = DiscourseWorkspaceGroups.workspace_sidebar_orders_for(current_user)
      if ordered_ids.present?
        sidebar_orders[@workspace.id.to_s] = ordered_ids
      else
        sidebar_orders.delete(@workspace.id.to_s)
      end
      DiscourseWorkspaceGroups.persist_workspace_sidebar_orders!(current_user, sidebar_orders)

      render json: { channel_ids: sidebar_orders[@workspace.id.to_s] || [] }
    end

    def update
      guardian.ensure_can_see!(@workspace)
      raise Discourse::InvalidAccess if !guardian.can_manage_workspace?(@workspace)

      workspace =
        ::DiscourseWorkspaceGroups::UpdateWorkspace.new(
          workspace: @workspace,
          user: current_user,
          description: params[:description],
          public_read: params[:public_read],
          members_can_create_channels: params[:members_can_create_channels],
          members_can_create_private_channels: params[:members_can_create_private_channels],
          auto_join_channel_ids: params[:auto_join_channel_ids],
        ).call

      context = build_channels_context([])

      render json: {
               workspace:
                 serialize_workspace(
                   **context.merge(workspace: workspace, all_active_channels: workspace_channels(archived: false)),
                 ),
             }
    end

    def update_channel
      guardian.ensure_can_see!(@workspace)
      channel = find_channel
      raise Discourse::InvalidAccess if !guardian.can_manage_workspace_channel?(channel)

      channel =
        ::DiscourseWorkspaceGroups::UpdateChannel.new(
          channel: channel,
          user: current_user,
          name: params.require(:name),
          description: params[:description],
          visibility: params[:visibility],
          channel_mode: params[:channel_mode],
          allow_channel_wide_mentions: params[:allow_channel_wide_mentions],
        ).call

      context = build_channels_context([channel])

      render json: { channel: serialize_channel(channel, **context) }
    end

    def join_channel
      guardian.ensure_can_see!(@workspace)
      channel = find_channel
      raise Discourse::InvalidAccess if !guardian.can_join_workspace_channel?(channel)

      ::DiscourseWorkspaceGroups::JoinChannel.new(channel: channel, user: current_user).call

      context = build_channels_context([channel])
      render json: { channel: serialize_channel(channel, **context) }
    end

    def leave_channel
      guardian.ensure_can_see!(@workspace)
      channel = find_channel
      raise Discourse::InvalidAccess if !guardian.can_leave_workspace_channel?(channel)

      ::DiscourseWorkspaceGroups::LeaveChannel.new(channel: channel, user: current_user).call

      context = build_channels_context([channel])
      render json: { channel: serialize_channel(channel, **context) }
    end

    def channel_access
      guardian.ensure_can_see!(@workspace)
      channel = find_channel
      raise Discourse::InvalidAccess if !guardian.can_manage_workspace_channel?(channel)

      render_channel_access(channel)
    end

    def add_channel_members
      guardian.ensure_can_see!(@workspace)
      channel = find_channel
      raise Discourse::InvalidAccess if !guardian.can_manage_workspace_channel?(channel)

      _usernames, users = users_from_usernames_param
      return if performed?

      ::DiscourseWorkspaceGroups::AddChannelMembers.new(
        channel: channel,
        acting_user: current_user,
        users: users,
      ).call

      render_channel_access(channel)
    end

    def remove_channel_member
      guardian.ensure_can_see!(@workspace)
      channel = find_channel
      raise Discourse::InvalidAccess if !guardian.can_manage_workspace_channel?(channel)

      target_user = User.find_by(id: params[:user_id].to_i)
      raise Discourse::NotFound if target_user.blank?

      ::DiscourseWorkspaceGroups::RemoveChannelMember.new(
        channel: channel,
        acting_user: current_user,
        target_user: target_user,
      ).call

      render_channel_access(channel)
    end

    def archive_channel
      guardian.ensure_can_see!(@workspace)
      channel = find_channel
      raise Discourse::InvalidAccess if !guardian.can_manage_workspace_channel?(channel)

      ::DiscourseWorkspaceGroups::SetChannelArchiveState.new(
        channel: channel,
        user: current_user,
        archived: true,
      ).call

      context = build_channels_context([channel])
      render json: { channel: serialize_channel(channel, **context) }
    end

    def unarchive_channel
      guardian.ensure_can_see!(@workspace)
      channel = find_channel
      raise Discourse::InvalidAccess if !guardian.can_manage_workspace_channel?(channel)

      ::DiscourseWorkspaceGroups::SetChannelArchiveState.new(
        channel: channel,
        user: current_user,
        archived: false,
      ).call

      context = build_channels_context([channel])
      render json: { channel: serialize_channel(channel, **context) }
    end

    private

    def ensure_plugin_enabled
      raise Discourse::NotFound if !SiteSetting.discourse_workspace_groups_enabled
    end

    def find_workspace
      @workspace = Category.find_by(id: params[:id].to_i)
      raise Discourse::NotFound if @workspace.blank?

      DiscourseWorkspaceGroups.sync_workspace_root_permissions!(@workspace)
    end

    def find_overview_workspace
      category_slug_path_with_id = "#{params.require(:category_slug_path)}/#{params.require(:category_id)}"
      @workspace = Category.find_by_slug_path_with_id(category_slug_path_with_id)
      raise Discourse::NotFound if @workspace.blank?

      DiscourseWorkspaceGroups.sync_workspace_root_permissions!(@workspace)
    end

    def find_channel
      channel = Category.find_by(id: params[:channel_id].to_i, parent_category_id: @workspace.id)
      raise Discourse::NotFound if channel.blank? || !channel.workspace_channel?

      channel
    end

    def build_channels_context(channels)
      group_ids = channels.filter_map(&:workspace_group_id)
      workspace_member = guardian.is_admin? || @workspace.workspace_group.users.where(id: current_user.id).exists?
      groups_by_id = Group.where(id: group_ids).index_by(&:id)
      joined_group_ids =
        if group_ids.present?
          GroupUser.where(user_id: current_user.id, group_id: group_ids).pluck(:group_id).to_set
        else
          Set.new
        end

      { groups_by_id: groups_by_id, joined_group_ids: joined_group_ids, workspace_member: workspace_member }
    end

    def visible_channels(channels, **context)
      channels.select { |category| visible_channel?(category, **context) }
    end

    def workspace_channels(archived:)
      categories =
        Category.where(parent_category_id: @workspace.id)
          .includes(topic: :first_post)
          .order(:position, :name)
          .to_a
      Category.preload_custom_fields(categories, Site.preloaded_category_custom_fields)

      categories
        .select(&:workspace_channel?)
        .select { |category| category.workspace_archived? == archived }
    end

    def visible_channel?(category, joined_group_ids:, workspace_member:, **)
      return true if guardian.is_admin?
      return true if category.workspace_visibility != VISIBILITY_PRIVATE && workspace_member

      joined_group_ids.include?(category.workspace_group_id)
    end

    def serialize_workspace(workspace_member:, workspace: @workspace, all_active_channels: nil, **)
      group = workspace.workspace_group
      about_post = workspace.topic&.first_post
      can_manage = guardian.can_manage_workspace?(workspace)
      auto_join_channels =
        if can_manage
          DiscourseWorkspaceGroups.workspace_auto_join_channels(
            workspace,
            candidates: all_active_channels,
          )
        else
          []
        end

      {
        id: workspace.id,
        name: workspace.name,
        path: workspace.url,
        can_create_channel: guardian.can_create_workspace_channel?(workspace),
        can_create_private_channel: guardian.can_create_private_workspace_channel?(workspace),
        can_manage: can_manage,
        member_count: group.present? ? group.group_users.count : 0,
        members_url: group_members_url(group),
        can_view_members: guardian.is_admin? || workspace_member,
        about_cooked: about_post&.cooked || workspace.description,
        about_raw: about_post&.raw,
        about_url: workspace.topic_url,
        public_read: workspace.workspace_root_public_read?,
        members_can_create_channels: workspace.workspace_members_can_create_channels?,
        members_can_create_private_channels: workspace.workspace_members_can_create_private_channels?,
        auto_join_channel_ids: auto_join_channels.map(&:id),
        auto_join_channel_options:
          can_manage ? serialize_auto_join_channel_options(all_active_channels || workspace_channels(archived: false)) : [],
      }
    end

    def serialize_auto_join_channel_options(channels)
      channels
        .select(&:workspace_channel?)
        .reject(&:workspace_archived?)
        .map do |channel|
          {
            id: channel.id,
            name: channel.name,
            visibility: channel.workspace_visibility,
          }
        end
    end

    def render_channel_access(channel)
      context = build_channels_context([channel])
      render json: {
               channel: serialize_channel(channel, **context),
               members: serialize_channel_members(channel),
             }
    end

    def serialize_channel(category, groups_by_id:, joined_group_ids:, workspace_member:)
      group = groups_by_id[category.workspace_group_id]
      joined = group.present? && joined_group_ids.include?(group.id)
      visible = visible_channel?(category, joined_group_ids: joined_group_ids, workspace_member: workspace_member)
      can_join = visible && !joined && category.workspace_visibility != VISIBILITY_PRIVATE && workspace_member
      can_leave = joined && DiscourseWorkspaceGroups.can_leave_channel_group?(group, current_user)
      can_manage = DiscourseWorkspaceGroups.can_manage_workspace_channel?(category, current_user)
      can_open_topics = joined || guardian.is_admin?
      archived = category.workspace_archived?

      {
        id: category.id,
        name: category.name,
        description: category.description_text,
        description_cooked: category.description,
        description_raw: category.topic&.first_post&.raw,
        visibility: category.workspace_visibility,
        mode: category.workspace_channel_mode,
        allow_channel_wide_mentions: category.category_channel&.allow_channel_wide_mentions,
        archived: archived,
        visible: visible,
        joined: joined,
        can_join: can_join,
        can_leave: can_leave,
        can_archive: can_manage && !archived,
        can_unarchive: can_manage && archived,
        can_open_topics: can_open_topics,
        can_view_members: joined,
        member_count: group.present? ? group.group_users.count : 0,
        members_url: group_members_url(group),
        topics_url: category.url,
        chat_channel_id: category.workspace_chat_enabled? ? category.category_channel&.id : nil,
        chat_channel: serialize_chat_channel(category),
      }
    end

    def serialize_chat_channel(category)
      return if !category.workspace_chat_enabled?

      chat_channel = category.category_channel
      return if chat_channel.blank?

      membership = chat_channel.membership_for(current_user)
      return if membership.blank?

      ::Chat::ChannelSerializer.new(
        chat_channel,
        scope: guardian,
        root: false,
        membership: membership,
      ).as_json
    end

    def serialize_channel_members(channel)
      group = channel.workspace_group
      return [] if group.blank?

      workspace_member_ids =
        @workspace.workspace_group.group_users.where(user_id: group.group_users.select(:user_id)).pluck(:user_id).to_set

      group
        .group_users
        .includes(:user)
        .to_a
        .sort_by { |group_user| [group_user.owner? ? 0 : 1, group_user.user.username_lower] }
        .map do |group_user|
          user = group_user.user
          guest = !workspace_member_ids.include?(user.id)

          {
            id: user.id,
            username: user.username,
            name: user.name,
            avatar_template: user.avatar_template,
            owner: group_user.owner?,
            guest: guest,
            can_remove:
              user.id != current_user.id &&
                DiscourseWorkspaceGroups.can_remove_channel_group_member?(group, user),
          }
        end
    end

    def users_from_usernames_param
      usernames =
        params
          .require(:usernames)
          .to_s
          .split(",")
          .map(&:strip)
          .reject(&:blank?)
          .uniq

      if usernames.blank?
        render_json_error(
          I18n.t("discourse_workspace_groups.errors.usernames_required"),
          status: :unprocessable_entity,
        )
        return
      end

      users_by_username =
        User.where(username_lower: usernames.map(&:downcase)).index_by(&:username_lower)
      missing_usernames = usernames.reject { |username| users_by_username.key?(username.downcase) }

      if missing_usernames.present?
        render_json_error(
          I18n.t(
            "discourse_workspace_groups.errors.unknown_users",
            usernames: missing_usernames.join(", "),
          ),
          status: :unprocessable_entity,
        )
        return
      end

      [usernames, usernames.map { |username| users_by_username.fetch(username.downcase) }]
    end

    def group_members_url(group)
      return if group.blank?

      "/g/#{group.name}"
    end
  end
end
