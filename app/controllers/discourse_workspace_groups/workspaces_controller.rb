# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class WorkspacesController < ::ApplicationController
    requires_login

    before_action :ensure_plugin_enabled
    before_action :find_workspace

    def show
      guardian.ensure_can_see!(@workspace)
      raise Discourse::NotFound if !@workspace.workspace_root?

      channels = Category.where(parent_category_id: @workspace.id).order(:position, :name).to_a
      Category.preload_custom_fields(channels, Site.preloaded_category_custom_fields)

      render json: {
               workspace: {
                 id: @workspace.id,
                 name: @workspace.name,
                 path: @workspace.url,
               },
               channels:
                 channels
                   .select(&:workspace_channel?)
                   .select { |category| guardian.can_see?(category) }
                   .map { |category| serialize_channel(category) },
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

    def serialize_channel(category)
      chat_channel = category.category_channel

      {
        id: category.id,
        name: category.name,
        description: category.description,
        visibility: category.workspace_visibility,
        topics_url: category.url,
        chat_url: chat_channel.present? ? "/chat/c/#{chat_channel.slug}/#{chat_channel.id}" : nil,
      }
    end
  end
end
