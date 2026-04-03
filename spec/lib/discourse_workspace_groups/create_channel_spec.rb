# frozen_string_literal: true

RSpec.describe DiscourseWorkspaceGroups::CreateChannel do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:other_user) { Fabricate(:user) }
  fab!(:category) { Fabricate(:category) }

  let!(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call
  end

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = false
  end

  it "creates private channels with only the creator as a member" do
    expect(workspace.workspace_group.name).to eq(
      DiscourseWorkspaceGroups.workspace_group_name(workspace),
    )

    expect {
      described_class.new(
        workspace: workspace,
        user: admin,
        name: "Secret Lab",
        description: nil,
        visibility: "private",
      ).call
    }.to change(Category, :count).by(1)

    channel = Category.last

    expect(channel.workspace_visibility).to eq("private")
    expect(channel.workspace_group.name).to eq(
      DiscourseWorkspaceGroups.channel_group_name(workspace, "Secret Lab"),
    )
    expect(channel.workspace_group.users).to contain_exactly(admin)
    expect(workspace.workspace_group.users).not_to include(other_user)
  end
end
