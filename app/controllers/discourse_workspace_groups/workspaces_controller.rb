# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class WorkspacesController < ::ApplicationController
    requires_login

    before_action :ensure_plugin_enabled
    before_action :find_workspace

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
        usernames: params[:usernames],
      ).call

      render json: {
               category_id: category.id,
               category_url: category.url,
               workspace_id: @workspace.id,
               visibility: category.workspace_visibility,
             }
    end

    private

    def ensure_plugin_enabled
      raise Discourse::NotFound if !SiteSetting.discourse_workspace_groups_enabled
    end

    def find_workspace
      @workspace = Category.find_by(id: params[:id].to_i)
      raise Discourse::NotFound if @workspace.blank?
    end
  end
end
