# frozen_string_literal: true

RSpec.describe "Empty workspace team" do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, active: true) }
  fab!(:category) { Fabricate(:category, name: "Empty team", user: admin) }

  let(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }
  let(:team_sidebar) { ".workspace-team-sidebar" }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    chat_system_bootstrap
    SiteSetting.enable_public_channels = true

    workspace.create_category_definition
    workspace.workspace_group.add(member)
  end

  it "opens the team sidebar with a create action and hides the category template" do
    sign_in(member)
    visit("#{workspace.url}/overview")

    expect(page).to have_css(".workspace-groups-overview__empty")
    expect(page).to have_no_css(".workspace-groups-overview__team-about")
    expect(page).to have_no_content("Replace this first paragraph")

    within(team_sidebar) do
      expect(page).to have_css(".workspace-team-sidebar__controls")
      expect(page).to have_css(".workspace-team-sidebar__empty", text: "No channels yet.")
      find(".workspace-team-sidebar__create-channel").click
    end

    expect(page).to have_css(".workspace-groups-create-channel-modal")
  end

  it "does not offer channel creation to members who cannot create channels" do
    workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_MEMBERS_CAN_CREATE_CHANNELS] = false
    workspace.save_custom_fields(true)

    sign_in(member)
    visit("#{workspace.url}/overview")

    within(team_sidebar) do
      expect(page).to have_css(".workspace-team-sidebar__empty", text: "No channels yet.")
      expect(page).to have_no_css(".workspace-team-sidebar__create-channel")
    end
  end
end
