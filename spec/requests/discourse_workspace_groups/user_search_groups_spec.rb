# frozen_string_literal: true

RSpec.describe "Mention autocomplete for workspace groups" do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, active: true, trust_level: 2) }
  fab!(:category) { Fabricate(:category, name: "Quantum", slug: "quantum", user: admin) }
  fab!(:outside_group) { Fabricate(:group, name: "quantum-readers", visibility_level: Group.visibility_levels[:public]) }

  let(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }
  let!(:channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Quantum dots",
      description: nil,
      visibility: "private",
    ).call
  end

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    workspace.workspace_group.add(member)
    channel.workspace_group.add(member)
    outside_group.add(member)
  end

  def group_names(user)
    sign_in(user)
    get "/u/search/users.json", params: { term: "quantum", include_groups: "true" }
    expect(response.status).to eq(200)
    response.parsed_body["groups"].map { |group| group["name"] }
  end

  it "does not offer team and channel groups to members" do
    expect(group_names(member)).to include("quantum-readers")
    expect(group_names(member)).not_to include(workspace.workspace_group.name, channel.workspace_group.name)
  end

  it "does not offer them to admins either" do
    expect(group_names(admin)).to include("quantum-readers")
    expect(group_names(admin)).not_to include(workspace.workspace_group.name, channel.workspace_group.name)
  end

  it "offers them again when the plugin is off" do
    names = [workspace.workspace_group.name, channel.workspace_group.name]
    SiteSetting.discourse_workspace_groups_enabled = false

    expect(group_names(member)).to include(*names)
  end
end
