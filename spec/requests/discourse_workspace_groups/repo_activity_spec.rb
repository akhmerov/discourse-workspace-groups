# frozen_string_literal: true

RSpec.describe "Workspace repository management" do
  fab!(:admin)
  fab!(:moderator)
  fab!(:owner, :user)
  fab!(:member, :user)
  fab!(:category) { Fabricate(:category, user: admin) }

  let(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(
      category: category,
      user: admin
    ).call
  end
  let(:channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Research",
      description: "Repository tests",
      visibility: "public"
    ).call
  end
  let(:chat_channel) { Chat::Channel.find_by(chatable: channel) }

  before do
    unless defined?(DiscourseRepoActivity)
      skip "Requires discourse-repo-activity"
    end
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.repo_activity_enabled = true
    SiteSetting.chat_enabled = true
    SiteSetting.enable_public_channels = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    workspace.workspace_group.add(owner)
    workspace.workspace_group.add(member)
    workspace.workspace_group.add(moderator)
    channel.workspace_group.add(owner)
    channel.workspace_group.add(member)
    channel.workspace_group.add(moderator)
    channel
      .workspace_group
      .group_users
      .find_by(user: owner)
      .update!(owner: true)
  end

  it "lets staff and channel owners manage repositories" do
    sign_in(admin)
    get "/repo-activity/channels/#{chat_channel.id}/connections.json"
    expect(response.status).to eq(200)
    sign_in(moderator)
    get "/repo-activity/channels/#{chat_channel.id}/connections.json"
    expect(response.status).to eq(200)
    sign_in(owner)
    post "/repo-activity/channels/#{chat_channel.id}/connections.json",
         params: {
           forge: "gitlab",
           host: "gitlab.tudelft.nl",
           repo_path: "group/nested/sim-tools"
         }
    expect(response.status).to eq(200)
    get "/repo-activity/channels/#{chat_channel.id}/connections.json"
    expect(
      response.parsed_body["connections"].map do |connection|
        connection["repo_path"]
      end
    ).to eq(["group/nested/sim-tools"])
  end

  it "denies ordinary members and revoked owners" do
    sign_in(member)
    get "/repo-activity/channels/#{chat_channel.id}/connections.json"
    expect(response.status).to eq(403)
    channel
      .workspace_group
      .group_users
      .find_by(user: owner)
      .update!(owner: false)
    sign_in(owner)
    get "/repo-activity/channels/#{chat_channel.id}/connections.json"
    expect(response.status).to eq(403)
  end
end
