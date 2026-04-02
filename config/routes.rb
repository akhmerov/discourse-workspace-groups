# frozen_string_literal: true

DiscourseWorkspaceGroups::Engine.routes.draw do
  get "/workspaces/:id" => "workspaces#show"
  post "/workspaces/:id/enable" => "workspaces#enable"
  post "/workspaces/:id/channels" => "workspaces#create_channel"
end
