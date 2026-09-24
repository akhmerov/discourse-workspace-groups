# frozen_string_literal: true

RSpec.describe "Workspace sidebar unread indicators" do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, active: true) }
  fab!(:other) { Fabricate(:user, active: true) }
  fab!(:category) { Fabricate(:category, name: "Unread workspace", user: admin) }

  let(:workspace) { DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call }

  def create_team_channel(name, user: admin)
    channel =
      DiscourseWorkspaceGroups::CreateChannel.new(
        workspace: workspace,
        user: user,
        name: name,
        description: nil,
        visibility: "public",
        channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_CHAT_ONLY,
      ).call
    channel.workspace_group.add(member)
    channel.workspace_group.add(other)
    chat_channel = Chat::Channel.find_by(chatable: channel)
    chat_channel.update!(threading_enabled: true)
    chat_channel.add(member)
    chat_channel.add(other)
    chat_channel
  end

  let!(:team_chat_channel) { create_team_channel("Team room") }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    chat_system_bootstrap
    SiteSetting.enable_public_channels = true
    workspace.workspace_group.add(member)
    workspace.workspace_group.add(other)
  end

  def row(name)
    find(".workspace-team-sidebar__row", text: name)
  end

  def row_unread?(name)
    row(name).has_css?(".chat-channel-unread-indicator", wait: 0)
  end

  # A thread the member tracks, with the channel itself fully read.
  def tracked_thread(channel)
    thread = Fabricate(:chat_thread, channel: channel, original_message_user: other, use_service: true)
    thread.add(member)
    channel.membership_for(member).update!(last_read_message_id: thread.original_message_id)
    thread
  end

  def post(channel, text, thread: nil)
    Fabricate(:chat_message, chat_channel: channel, thread: thread, user: other, message: text, use_service: true)
  end

  def read_elsewhere(channel, message)
    Chat::UpdateUserChannelLastRead.call(
      guardian: member.guardian,
      params: {
        channel_id: channel.id,
        message_id: message.id,
      },
    )
  end

  def tracking_requests
    page.evaluate_script(<<~JS)
      performance.getEntriesByType("resource").filter((entry) =>
        entry.name.includes("/workspace-groups/workspaces/") &&
        entry.name.includes("/chat-tracking")
      ).length
    JS
  end

  def wait_for_sidebar_tracking
    expect(page).to have_css(".workspace-team-sidebar__row", text: "Team room")
    try_until_success { expect(tracking_requests).to be > 0 }
  end

  it "shows a thread-only unread" do
    post(team_chat_channel, "a reply", thread: tracked_thread(team_chat_channel))

    sign_in(member)
    visit(category.url)
    wait_for_sidebar_tracking

    expect(row("Team room")).to have_css(".chat-channel-unread-indicator")
  end

  it "clears the dot once the member reads a new thread reply" do
    thread = tracked_thread(team_chat_channel)

    sign_in(member)
    visit("/chat/c/#{team_chat_channel.slug}/#{team_chat_channel.id}")
    wait_for_sidebar_tracking
    expect(row_unread?("Team room")).to eq(false)

    post(team_chat_channel, "new while open", thread: thread)
    expect(row("Team room")).to have_css(".chat-channel-unread-indicator")

    visit("/chat/c/#{team_chat_channel.slug}/#{team_chat_channel.id}/t/#{thread.id}")
    expect(page).to have_css(".chat-thread .chat-message-text", text: "new while open")
    try_until_success do
      expect(thread.membership_for(member).reload.last_read_message_id).to eq(thread.reload.last_message_id)
    end

    expect(row("Team room")).to have_no_css(".chat-channel-unread-indicator")
  end

  it "clears the dot when the member reads the channel elsewhere" do
    message = post(team_chat_channel, "read me elsewhere")

    sign_in(member)
    visit(category.url)
    wait_for_sidebar_tracking
    expect(row("Team room")).to have_css(".chat-channel-unread-indicator")

    read_elsewhere(team_chat_channel, message)

    expect(row("Team room")).to have_no_css(".chat-channel-unread-indicator")
  end

  it "lists a channel a teammate creates while the page is open and shows its messages" do
    sign_in(member)
    visit(category.url)
    wait_for_sidebar_tracking
    # Let the page's message bus subscriptions reach the server first.
    sleep 2

    fresh = create_team_channel("Fresh room", user: other)
    expect(page).to have_css(".workspace-team-sidebar__row", text: "Fresh room")

    post(fresh, "first message")
    expect(row("Fresh room")).to have_css(".chat-channel-unread-indicator")
  end

  context "when the member follows more channels than core loads" do
    before do
      # Core loads followed public channels alphabetically, at most 100.
      100.times do |index|
        Fabricate(:category_channel, name: "Aa filler #{index.to_s.rjust(3, "0")}").add(member)
      end
    end

    it "still lists the team's channels and shows their new messages" do
      late = create_team_channel("Zz late room")

      sign_in(member)
      visit(category.url)
      wait_for_sidebar_tracking
      expect(page).to have_css(".workspace-team-sidebar__row", text: "Zz late room")
      expect(row_unread?("Zz late room")).to eq(false)

      post(late, "hello")

      expect(row("Zz late room")).to have_css(".chat-channel-unread-indicator")
    end

    it "clears the dot of a late channel after reading its new thread reply" do
      late = create_team_channel("Zz late room")
      thread = tracked_thread(late)

      sign_in(member)
      visit("/chat/c/#{late.slug}/#{late.id}")
      expect(page).to have_css(".chat-channel[data-id='#{late.id}']")

      post(late, "late reply", thread: thread)
      expect(row("Zz late room")).to have_css(".chat-channel-unread-indicator")

      visit("/chat/c/#{late.slug}/#{late.id}/t/#{thread.id}")
      expect(page).to have_css(".chat-thread .chat-message-text", text: "late reply")
      try_until_success do
        expect(thread.membership_for(member).reload.last_read_message_id).to eq(thread.reload.last_message_id)
      end

      expect(row("Zz late room")).to have_no_css(".chat-channel-unread-indicator")
    end

    it "keeps a read made while the sidebar's tracking request is in flight" do
      late = create_team_channel("Zz late room")
      message = post(late, "read during load")
      held = Queue.new
      holding = true

      sign_in(member)
      visit("/about")
      origin = page.evaluate_script("location.origin")

      page.driver.with_playwright_page do |pw_page|
        pw_page.route(
          %r{/workspace-groups/workspaces/\d+/chat-tracking},
          ->(route, _request) do
            if holding
              holding = false
              held << route
            else
              route.continue
            end
          end,
        )
      end

      # Capybara's visit waits for pending requests, which would never settle here.
      page.driver.with_playwright_page { |pw_page| pw_page.goto("#{origin}#{category.url}") }

      route = held.pop(timeout: 10)
      expect(route).to be_present
      stale_response = route.fetch
      read_elsewhere(late, message)

      # Capybara waits for pending requests, so check the page directly while
      # the tracking request is held.
      read_applied = <<~JS
        () => {
          const manager = Discourse.lookup("service:chat-channels-manager");
          const channel = manager.channels.find((c) => c.id === #{late.id});
          return !!channel && channel.tracking.unreadCount === 0;
        }
      JS
      page.driver.with_playwright_page do |pw_page|
        deadline = 10.seconds.from_now
        sleep 0.2 until pw_page.evaluate(read_applied) || Time.zone.now > deadline
      end

      route.fulfill(response: stale_response)
      sleep 1

      expect(row("Zz late room")).to have_no_css(".chat-channel-unread-indicator")
    end
  end
end
