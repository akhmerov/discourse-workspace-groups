# frozen_string_literal: true

require "securerandom"

RSpec.describe Chat::ChannelFetcher do
  fab!(:admin) do
    suffix = SecureRandom.hex(4)
    Fabricate(:admin, username: "wa#{suffix}", email: "workspace-admin-#{suffix}@example.com")
  end
  fab!(:member) do
    suffix = SecureRandom.hex(4)
    Fabricate(:user, active: true, username: "wm#{suffix}", email: "wm-#{suffix}@example.com")
  end
  fab!(:category) { Fabricate(:category, name: "Workspace #{SecureRandom.hex(4)}", user: admin) }

  let!(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = true
    SiteSetting.enable_public_channels = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]

    workspace.workspace_group.add(member)
  end

  def create_channel(name)
    channel =
      DiscourseWorkspaceGroups::CreateChannel.new(
        workspace: workspace,
        user: admin,
        name: "#{name} #{SecureRandom.hex(4)}",
        description: nil,
        visibility: "public",
      ).call
    channel.workspace_group.add(member)
    chat_channel_for(channel).add(member)
    channel
  end

  def chat_channel_for(channel)
    Chat::Channel.find_by!(chatable_type: "Category", chatable_id: channel.id)
  end

  it "closes archived workspace chat channels" do
    channel = create_channel("Archive")

    DiscourseWorkspaceGroups::SetChannelArchiveState.new(
      channel: channel,
      user: admin,
      archived: true,
    ).call

    expect(chat_channel_for(channel).status).to eq("closed")
  end

  it "excludes archived workspace channels from allowed chat channel ids even if stale open" do
    active_channel = create_channel("Active")
    archived_channel = create_channel("Archive")

    DiscourseWorkspaceGroups::SetChannelArchiveState.new(
      channel: archived_channel,
      user: admin,
      archived: true,
    ).call
    chat_channel_for(archived_channel).update!(status: "open")

    visible_chat_channel_ids =
      described_class.secured_public_channels(
        Guardian.new(member),
        status: :open,
        following: true,
        limit: 100,
      ).map(&:id)

    expect(visible_chat_channel_ids).to include(chat_channel_for(active_channel).id)
    expect(visible_chat_channel_ids).not_to include(chat_channel_for(archived_channel).id)
  end
end
