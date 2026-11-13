# frozen_string_literal: true

RSpec.describe "Workspace repository settings" do
  fab!(:admin)
  fab!(:owner, :user)
  fab!(:category) { Fabricate(:category, user: admin) }

  let(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call
  end
  let(:channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Research",
      description: "Repository tests",
      visibility: "public",
    ).call
  end
  let(:chat_channel) { Chat::Channel.find_by(chatable: channel) }

  before do
    skip "Requires discourse-repo-activity" unless defined?(DiscourseRepoActivity)
    chat_system_bootstrap(owner)
    SiteSetting.repo_activity_enabled = true
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.navigation_menu = "sidebar"
    workspace.workspace_group.add(owner)
    channel.workspace_group.add(owner)
    channel.workspace_group.group_users.find_by(user: owner).update!(owner: true)
    chat_channel.add(owner)
    sign_in(owner)
  end

  it "opens feature-owned repository management for a channel owner" do
    DiscourseRepoActivity::Connection.create!(
      chat_channel: chat_channel,
      created_by: owner,
      forge: "github",
      host: "github.com",
      repo_path: "acme/sim-tools",
    )
    visit("/chat/c/#{chat_channel.slug}/#{chat_channel.id}")
    find(".workspace-channel-context__settings", visible: :all).click
    find(".workspace-groups-repositories").click
    expect(page).to have_css(".repo-activity__manager", text: "Add repository")
    expect(page).to have_css(".repo-manager__row", text: "acme/sim-tools")
    expect(page).to have_no_css(".repo-activity__toggles")
    expect(page).to have_css(".repo-manager__menu-trigger")
  end
end
