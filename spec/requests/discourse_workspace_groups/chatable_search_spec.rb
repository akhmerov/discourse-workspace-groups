# frozen_string_literal: true

RSpec.describe "Chat quick palette search for workspace channels" do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, active: true, trust_level: 2) }
  fab!(:category) { Fabricate(:category, name: "Quantum", slug: "quantum", user: admin) }
  fab!(:outside_group) { Fabricate(:group, name: "quantum-readers", visibility_level: Group.visibility_levels[:public]) }

  let(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }

  def create_channel(name)
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: name,
      description: nil,
      visibility: "public",
    ).call.tap { |channel| channel.workspace_group.add(member) }
  end

  let!(:delft) { create_channel("Delft") }
  let!(:quantum_dots) { create_channel("Quantum dots") }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = true
    SiteSetting.enable_public_channels = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.direct_message_enabled_groups = Group::AUTO_GROUPS[:everyone]
    workspace.workspace_group.add(member)
    outside_group.add(member)
    sign_in(member)
  end

  def search(term)
    get "/chat/api/chatables.json", params: { term: term }
    expect(response.status).to eq(200)
    response.parsed_body
  end

  def channel_names(body)
    body["category_channels"].map { |item| item.dig("model", "title") }
  end

  it "does not offer team and channel groups as message targets" do
    body = search("quantum")

    group_names = body["groups"].map { |item| item.dig("model", "name") }
    expect(group_names).to include("quantum-readers")
    expect(group_names).not_to include(workspace.workspace_group.name, delft.workspace_group.name)
  end

  it "does not match channels only through the team part of their slug" do
    expect(Chat::Channel.find_by(chatable: delft).slug).to start_with("quantum-")

    expect(channel_names(search("quantum"))).to eq(["Quantum dots"])
    expect(channel_names(search("delf"))).to eq(["Delft"])
  end

  it "does not offer joinable channels only through the team slug" do
    delft.workspace_group.remove(member)

    get "/workspace-groups/joinable-channels.json", params: { term: "quantum" }

    expect(response.status).to eq(200)
    expect(response.parsed_body["channels"].map { |channel| channel["name"] }).not_to include("Delft")
  end
end
