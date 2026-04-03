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

      channels = Category.where(parent_category_id: @workspace.id).order(:position, :name).to_a
      Category.preload_custom_fields(channels, Site.preloaded_category_custom_fields)
      context = build_channels_context(channels)

      render json: {
               workspace: serialize_workspace(**context),
               channels:
                 channels
                   .select(&:workspace_channel?)
                   .select { |category| visible_channel?(category, **context) }
                   .map { |category| serialize_channel(category, **context) },
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
      ).call

      render json: {
               category_id: category.id,
               category_url: category.url,
               workspace_id: @workspace.id,
               visibility: category.workspace_visibility,
             }
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

    def visible_channel?(category, joined_group_ids:, workspace_member:, **)
      return true if guardian.is_admin?
      return true if category.workspace_visibility != VISIBILITY_PRIVATE && workspace_member

      joined_group_ids.include?(category.workspace_group_id)
    end

    def serialize_workspace(workspace_member:, **)
      group = @workspace.workspace_group
      about_post = @workspace.topic&.first_post

      {
        id: @workspace.id,
        name: @workspace.name,
        path: @workspace.url,
        can_create_channel: guardian.can_create_workspace_channel?(@workspace),
        member_count: group.present? ? group.group_users.count : 0,
        members_url: group_members_url(group),
        can_view_members: guardian.is_admin? || workspace_member,
        about_cooked: about_post&.cooked || @workspace.description,
        about_url: @workspace.topic_url,
      }
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
        visibility: category.workspace_visibility,
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
        chat_channel_id: category.category_channel&.id,
        chat_channel: serialize_chat_channel(category),
      }
    end

    def serialize_chat_channel(category)
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
