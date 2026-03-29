# frozen_string_literal: true

DiscourseWorkspaceGroups::Engine.routes.draw do
  post "/workspaces/:id/enable" => "workspaces#enable"
  post "/workspaces/:id/channels" => "workspaces#create_channel"
end
