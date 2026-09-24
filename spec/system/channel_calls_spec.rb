# frozen_string_literal: true

RSpec.describe "Channel calls" do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, active: true) }
  fab!(:category) { Fabricate(:category, name: "Calls workspace", user: admin) }

  let(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }
  let(:channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Lab calls",
      description: "Lab channel",
      visibility: "public",
    ).call
  end
  let(:chat_channel) { Chat::Channel.find_by(chatable: channel) }
  let(:call_link) { ".workspace-channel-context__call[href='/workspace-voice/channels/#{channel.id}']" }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    chat_system_bootstrap
    SiteSetting.enable_public_channels = true
    SiteSetting.voice_enabled = true

    workspace.workspace_group.add(member)
    channel.workspace_group.add(member)
  end

  it "offers a call in every channel without setting up a room" do
    sign_in(member)
    visit("/chat/c/#{chat_channel.slug}/#{chat_channel.id}")

    expect(page).to have_css(call_link, visible: :all)
    expect(DiscourseWorkspaceGroups::VoiceBinding.where(source_id: channel.id)).to be_empty
  end

  it "hides the call button when the workspace turns calls off" do
    workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_CHANNEL_CALLS] = false
    workspace.save_custom_fields(true)
    sign_in(member)
    visit("/chat/c/#{chat_channel.slug}/#{chat_channel.id}")

    expect(page).to have_css(".workspace-channel-context__members", visible: :all)
    expect(page).to have_no_css(call_link, visible: :all)
  end
end
