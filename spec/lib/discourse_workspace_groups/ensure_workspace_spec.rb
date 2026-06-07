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

  it "does not rewrite already-synced public root permissions" do
    workspace = described_class.new(category: category, user: admin, public_read: true).call

    expect(workspace).not_to receive(:set_permissions)
    expect(workspace).not_to receive(:save!)

    DiscourseWorkspaceGroups.sync_workspace_root_permissions!(workspace)
  end

  it "does not grant everyone access by default" do
    workspace = described_class.new(category: category, user: admin).call

    expect(workspace.workspace_root_public_read?).to eq(false)
    expect(workspace.workspace_members_can_create_channels?).to eq(true)
    expect(workspace.workspace_members_can_create_private_channels?).to eq(true)
    expect(workspace.category_groups.find_by(group_id: Group::AUTO_GROUPS[:everyone])).to be_nil
  end

  it "grants team owners trust level 3" do
    user =
      Fabricate(
        :trust_level_1,
        active: true,
        username: "owner#{SecureRandom.hex(4)}",
        email: "workspace-owner-#{SecureRandom.hex(4)}@example.com",
      )

    workspace = described_class.new(category: category, user: user).call

    expect(workspace.workspace_group.group_users.find_by(user: user)).to be_owner
    expect(user.reload.trust_level).to eq(TrustLevel[3])
  end

  it "recalculates trust level when a team owner is demoted" do
    user =
      Fabricate(
        :trust_level_1,
        active: true,
        username: "demoted#{SecureRandom.hex(4)}",
        email: "workspace-demoted-#{SecureRandom.hex(4)}@example.com",
      )
    workspace = described_class.new(category: category, user: user).call

    workspace.workspace_group.group_users.find_by!(user: user).update!(owner: false)
    DiscourseWorkspaceGroups.recalculate_workspace_owner_trust_level!(workspace.workspace_group, user)

    expect(user.reload.trust_level).to be < TrustLevel[3]
  end

  it "keeps trust level 3 when demoted from one team while still owning another" do
    user =
      Fabricate(
        :trust_level_1,
        active: true,
        username: "multi#{SecureRandom.hex(4)}",
        email: "workspace-multi-owner-#{SecureRandom.hex(4)}@example.com",
      )
    first_workspace = described_class.new(category: category, user: user).call
    second_category = Fabricate(:category, name: "Second Workspace #{SecureRandom.hex(4)}", user: admin)
    described_class.new(category: second_category, user: user).call

    first_workspace.workspace_group.group_users.find_by!(user: user).update!(owner: false)
    DiscourseWorkspaceGroups.recalculate_workspace_owner_trust_level!(first_workspace.workspace_group, user)

    expect(user.reload.trust_level).to eq(TrustLevel[3])
  end
end
