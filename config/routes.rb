# frozen_string_literal: true

DiscourseWorkspaceGroups::Engine.routes.draw do
  get "/workspaces/:id" => "workspaces#show"
  put "/workspaces/:id" => "workspaces#update"
  get "/workspaces/:id/archived-channels" => "workspaces#archived_channels"
  post "/workspaces/:id/enable" => "workspaces#enable"
  post "/workspaces/:id/channels" => "workspaces#create_channel"
  put "/workspaces/:id/channels/:channel_id" => "workspaces#update_channel"
  post "/workspaces/:id/channels/:channel_id/membership" => "workspaces#join_channel"
  delete "/workspaces/:id/channels/:channel_id/membership" => "workspaces#leave_channel"
  get "/workspaces/:id/channels/:channel_id/access" => "workspaces#channel_access"
  post "/workspaces/:id/channels/:channel_id/access" => "workspaces#add_channel_members"
  delete "/workspaces/:id/channels/:channel_id/access/:user_id" => "workspaces#remove_channel_member"
  post "/workspaces/:id/channels/:channel_id/archive" => "workspaces#archive_channel"
  delete "/workspaces/:id/channels/:channel_id/archive" => "workspaces#unarchive_channel"
end
