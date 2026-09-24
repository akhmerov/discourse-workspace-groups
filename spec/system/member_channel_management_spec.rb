# frozen_string_literal: true

RSpec.describe "Member channel management" do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, active: true) }
  fab!(:category) { Fabricate(:category, name: "Lab workspace", user: admin) }

  let(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }
  let(:channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Lab notes",
      description: "Lab channel",
      visibility: "public",
    ).call
  end
  let(:chat_channel) { Chat::Channel.find_by(chatable: channel) }
  let(:settings_modal) { ".workspace-groups-channel-settings-modal" }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    chat_system_bootstrap
    SiteSetting.enable_public_channels = true
    # The workspace sidebar depends on Voice's client services.
    SiteSetting.voice_enabled = true if SiteSetting.respond_to?(:voice_enabled)

    workspace.workspace_group.add(member)
    channel.workspace_group.add(member)
    workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_MEMBERS_CAN_MANAGE_CHANNELS] = true
    workspace.save_custom_fields(true)
  end

  it "lets a channel member edit the channel header from chat" do
    sign_in(member)
    visit("/chat/c/#{chat_channel.slug}/#{chat_channel.id}")

    find(".workspace-channel-context__settings", visible: :all).click

    within(settings_modal) do
      expect(page).to have_no_css(".workspace-groups-create-channel-modal__input")
      find("textarea").fill_in(with: "Links: [handbook](https://example.com/handbook)")
      find(".btn-primary").click
    end

    expect(page).to have_no_css(settings_modal)
    expect(page).to have_css(".workspace-channel-context__description a[href='https://example.com/handbook']", visible: :all)
    expect(channel.reload.topic.first_post.raw).to eq("Links: [handbook](https://example.com/handbook)")
  end

  it "lets a workspace manager turn the setting off" do
    sign_in(admin)
    visit("#{category.url}/overview")

    find(".workspace-groups-overview__settings-button").click
    find(".d-toggle-switch", text: I18n.t("js.discourse_workspace_groups.members_can_manage_channels"))
      .find(".d-toggle-switch__checkbox-slider")
      .click
    find(".d-modal .btn-primary").click

    expect(page).to have_no_css(".d-modal")
    expect(workspace.reload.workspace_members_can_manage_channels?).to eq(false)
  end
end
