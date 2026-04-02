# frozen_string_literal: true

DiscourseWorkspaceGroups::Engine.routes.draw do
  get "/workspaces/:id" => "workspaces#show"
  post "/workspaces/:id/enable" => "workspaces#enable"
  post "/workspaces/:id/channels" => "workspaces#create_channel"
  post "/workspaces/:id/channels/:channel_id/membership" => "workspaces#join_channel"
  delete "/workspaces/:id/channels/:channel_id/membership" => "workspaces#leave_channel"
end
