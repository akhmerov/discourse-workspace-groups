# frozen_string_literal: true

RSpec.describe "Workspace sidebar" do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, active: true) }
  fab!(:category) { Fabricate(:category, name: "Sidebar workspace", user: admin) }
  fab!(:outside_channel) { Fabricate(:category_channel, name: "Outside team") }

  let(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }
  let(:team_channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Team room",
      description: nil,
      visibility: "public",
    ).call
  end
  let(:team_chat_channel) { Chat::Channel.find_by(chatable: team_channel) }
  let(:core_chat_section) { ".sidebar-section-wrapper[data-section-name='chat-channels']" }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    chat_system_bootstrap
    SiteSetting.enable_public_channels = true

    workspace.workspace_group.add(member)
    team_channel.workspace_group.add(member)
    outside_channel.add(member)
  end

  it "lists only channels outside the user's teams in core chat's forum sidebar" do
    sign_in(member)
    visit("/latest")

    within(core_chat_section) do
      expect(page).to have_css(".channel-#{outside_channel.id}")
      expect(page).to have_no_css(".channel-#{team_chat_channel.id}")
    end
  end
end
