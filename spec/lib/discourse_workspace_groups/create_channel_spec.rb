# frozen_string_literal: true

require "securerandom"

RSpec.describe DiscourseWorkspaceGroups::CreateChannel do
  fab!(:admin) do
    suffix = SecureRandom.hex(4)
    Fabricate(:admin, username: "wa#{suffix}", email: "workspace-admin-#{suffix}@example.com")
  end
  fab!(:other_user) do
    suffix = SecureRandom.hex(4)
    Fabricate(:user, username: "wu#{suffix}", email: "workspace-user-#{suffix}@example.com")
  end
  fab!(:category) { Fabricate(:category, name: "Workspace #{SecureRandom.hex(4)}", user: admin) }

  let!(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call
  end

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = false
  end

  it "creates private channels with only the creator as a member" do
    channel_name = "Secret Lab #{SecureRandom.hex(4)}"

    expect(workspace.workspace_group.name).to eq(
      DiscourseWorkspaceGroups.workspace_group_name(workspace),
    )

    expect {
        described_class.new(
          workspace: workspace,
          user: admin,
          name: channel_name,
          description: nil,
          visibility: "private",
        ).call
    }.to change(Category, :count).by(1)

    channel = Category.last

    expect(channel.workspace_visibility).to eq("private")
    expect(channel.workspace_group.name).to eq(
      DiscourseWorkspaceGroups.channel_group_name(workspace, channel_name),
    )
    expect(channel.workspace_group.users).to contain_exactly(admin)
    expect(workspace.workspace_group.users).not_to include(other_user)
    expect(
      workspace.reload.category_groups.find_by(group_id: channel.workspace_group.id).permission_type,
    ).to eq(CategoryGroup.permission_types[:readonly])
  end
end
