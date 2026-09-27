# frozen_string_literal: true

RSpec.describe "Workspace sidebar active channel" do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, active: true) }
  fab!(:category) { Fabricate(:category, name: "Active workspace", user: admin) }

  let(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }

  def create_channel(name)
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: name,
      description: nil,
      visibility: "public",
      channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_BOTH,
    ).call
  end

  let!(:first_channel) { create_channel("First room") }
  let!(:second_channel) { create_channel("Second room") }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    chat_system_bootstrap
    SiteSetting.enable_public_channels = true
    workspace.workspace_group.add(member)
    first_channel.workspace_group.add(member)
    second_channel.workspace_group.add(member)
  end

  def active_links
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".workspace-team-sidebar__main-link.active")].map((link) => link.innerText.trim())
    JS
  end

  it "highlights only the channel being viewed" do
    sign_in(member)
    visit(first_channel.url)
    expect(page).to have_css(".workspace-team-sidebar__main-link.active", text: "First room")
    expect(active_links).to eq(["First room"])

    find(".workspace-team-sidebar__main-link", text: "Second room").click
    expect(page).to have_current_path(%r{second-room})
    expect(page).to have_css(".workspace-team-sidebar__main-link.active", text: "Second room")
    expect(active_links).to eq(["Second room"])
  end

  it "insets the highlighted channel's icon like core sidebar links" do
    sign_in(member)
    visit(first_channel.url)
    expect(page).to have_css(".workspace-team-sidebar__main-link.active", text: "First room")

    boxes = page.evaluate_script(<<~JS)
      [
        document.querySelector(".workspace-team-sidebar__main-link.active"),
        [...document.querySelectorAll(".sidebar-section-link.sidebar-row")].find(
          (link) => !link.closest(".workspace-team-sidebar__row") && link.getBoundingClientRect().width
        ),
      ].map((link) => ({
        left: link.getBoundingClientRect().left,
        iconLeft: link.querySelector(".sidebar-section-link-prefix").getBoundingClientRect().left,
      }))
    JS
    channel, core = boxes

    expect(channel["left"]).to be_within(0.5).of(core["left"])
    expect(channel["iconLeft"]).to be_within(0.5).of(core["iconLeft"])
  end
end
