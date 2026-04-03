# frozen_string_literal: true

require "securerandom"

RSpec.describe "workspace channel chat sync on direct group add" do
  fab!(:admin) do
    suffix = SecureRandom.hex(4)
    Fabricate(:admin, username: "wa#{suffix}", email: "workspace-admin-#{suffix}@example.com")
  end
  fab!(:other_user) do
    suffix = SecureRandom.hex(4)
    Fabricate(
      :user,
      active: true,
      username: "wu#{suffix}",
      email: "workspace-user-#{suffix}@example.com",
    )
  end
  fab!(:category) { Fabricate(:category, name: "Workspace #{SecureRandom.hex(4)}", user: admin) }

  let(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call
  end

  let(:channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Secret Lab #{SecureRandom.hex(4)}",
      description: nil,
      visibility: "private",
    ).call
  end

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = true
    SiteSetting.enable_public_channels = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
  end

  def chat_channel
    Chat::Channel.find_by(chatable_type: "Category", chatable_id: channel.id)
  end

  def chat_membership
    chat_channel&.membership_for(other_user)
  end

  it "adds the paired chat membership when a user is added directly to the channel group" do
    expect(chat_membership).to be_nil

    expect { channel.workspace_group.add(other_user) }.to change { chat_membership.present? }.from(false).to(true)

    expect(chat_membership.following).to eq(true)
  end
end
