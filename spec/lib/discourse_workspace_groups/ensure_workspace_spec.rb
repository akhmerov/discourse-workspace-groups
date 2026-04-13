# frozen_string_literal: true

require "securerandom"

RSpec.describe DiscourseWorkspaceGroups::EnsureWorkspace do
  fab!(:admin) do
    suffix = SecureRandom.hex(4)
    Fabricate(:admin, username: "wa#{suffix}", email: "workspace-admin-#{suffix}@example.com")
  end

  fab!(:category) { Fabricate(:category, name: "Workspace #{SecureRandom.hex(4)}", user: admin) }

  before { SiteSetting.discourse_workspace_groups_enabled = true }

  it "can mark a workspace root as publicly readable" do
    workspace = described_class.new(category: category, user: admin, public_read: true).call

    expect(workspace.workspace_root_public_read?).to eq(true)
    expect(workspace.category_groups.find_by(group_id: Group::AUTO_GROUPS[:everyone]).permission_type).to eq(
      CategoryGroup.permission_types[:readonly],
    )
  end

  it "does not grant everyone access by default" do
    workspace = described_class.new(category: category, user: admin).call

    expect(workspace.workspace_root_public_read?).to eq(false)
    expect(workspace.workspace_members_can_create_channels?).to eq(true)
    expect(workspace.workspace_members_can_create_private_channels?).to eq(true)
    expect(workspace.category_groups.find_by(group_id: Group::AUTO_GROUPS[:everyone])).to be_nil
  end
end
