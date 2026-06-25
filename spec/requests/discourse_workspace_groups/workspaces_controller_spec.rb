# frozen_string_literal: true

require "securerandom"

RSpec.describe DiscourseWorkspaceGroups::WorkspacesController do
  fab!(:admin) do
    suffix = SecureRandom.hex(4)
    Fabricate(:admin, username: "wa#{suffix}", email: "workspace-admin-#{suffix}@example.com")
  end
  fab!(:workspace_member) do
    suffix = SecureRandom.hex(4)
    Fabricate(
      :user,
      active: true,
      username: "wm#{suffix}",
      email: "workspace-member-#{suffix}@example.com",
    )
  end
  fab!(:guest_user) do
    suffix = SecureRandom.hex(4)
    Fabricate(
      :user,
      active: true,
      username: "wg#{suffix}",
      email: "workspace-guest-#{suffix}@example.com",
    )
  end
  fab!(:other_workspace_member) do
    suffix = SecureRandom.hex(4)
    Fabricate(
      :user,
      active: true,
      username: "wo#{suffix}",
      email: "workspace-other-#{suffix}@example.com",
    )
  end
  fab!(:category) { Fabricate(:category, name: "Workspace #{SecureRandom.hex(4)}", user: admin) }

  let(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call
  end

  let(:private_channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Steering #{SecureRandom.hex(4)}",
      description: nil,
      visibility: "private",
    ).call
  end

  let(:public_channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Updates #{SecureRandom.hex(4)}",
      description: nil,
      visibility: "public",
    ).call
  end

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = true
    SiteSetting.enable_public_channels = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]

    workspace.workspace_group.add(workspace_member)
    workspace.workspace_group.add(other_workspace_member)
  end

  def category_chat_channel(category)
    Chat::Channel.find_by(chatable_type: "Category", chatable_id: category.id)
  end

  describe "#show" do
    it "shows only joined channels to non-workspace guests" do
      private_channel.workspace_group.add(guest_user)
      public_channel

      guest_guardian = Guardian.new(guest_user.reload)
      expect(guest_guardian.can_see_category?(workspace.reload)).to eq(true)
      expect(guest_guardian.can_create_topic_on_category?(workspace.reload)).to eq(false)

      sign_in(guest_user.reload)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("workspace", "can_view_members")).to eq(false)
      expect(response.parsed_body.dig("workspace", "member_count")).to be_nil
      expect(response.parsed_body.dig("workspace", "members_url")).to be_nil
      expect(response.parsed_body["channels"].map { |channel| channel["id"] }).to eq([private_channel.id])
    end

    it "shows public channel member metadata to workspace members who have not joined the channel" do
      public_channel

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body["channels"].find { |channel| channel["id"] == public_channel.id }
      expect(payload["can_view_members"]).to eq(true)
      expect(payload["member_count"]).to eq(1)
      expect(payload["members_url"]).to eq("/g/#{public_channel.workspace_group.name}")
    end

    it "routes owners to the native group members page" do
      private_channel

      sign_in(admin)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("workspace", "members_url")).to eq("/g/#{workspace.workspace_group.name}")
      expect(
        response.parsed_body["channels"].find { |channel| channel["id"] == private_channel.id }[
          "members_url"
        ],
      ).to eq("/g/#{private_channel.workspace_group.name}")
    end

    it "routes non-owners to the same native group members page" do
      public_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("workspace", "members_url")).to eq(
        "/g/#{workspace.workspace_group.name}",
      )
      expect(
        response.parsed_body["channels"].find { |channel| channel["id"] == public_channel.id }[
          "members_url"
        ],
      ).to eq("/g/#{public_channel.workspace_group.name}")
    end

    it "preserves cooked channel descriptions with links in the payload" do
      linked_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Docs #{SecureRandom.hex(4)}",
          description: "Read [the docs](https://example.com/docs).",
          visibility: "public",
        ).call
      linked_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body["channels"].find { |channel| channel["id"] == linked_channel.id }
      expect(payload["description"]).to eq("Read the docs.")
      expect(payload["description_cooked"]).to include("href=\"https://example.com/docs\"")
      expect(payload["description_raw"]).to eq("Read [the docs](https://example.com/docs).")
      expect(payload["color"]).to eq(linked_channel.color)
      expect(payload["style_type"]).to eq(linked_channel.style_type)
    end

    it "only preloads active channels and reports archived channel count separately" do
      public_channel
      archived_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Archive #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
        ).call
      DiscourseWorkspaceGroups::SetChannelArchiveState.new(
        channel: archived_channel,
        user: admin,
        archived: true,
      ).call

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["archived_channel_count"]).to eq(1)
      expect(response.parsed_body["channels"].map { |channel| channel["id"] }).to eq([public_channel.id])
    end

    it "returns last activity from the newest enabled category or chat activity and excludes category about topics" do
      public_channel.reload.topic.update!(bumped_at: 1.hour.ago)
      topic_time = 3.days.ago
      chat_time = 2.days.ago
      Fabricate(:topic, category: public_channel, user: admin, bumped_at: topic_time)
      chat_channel = category_chat_channel(public_channel)
      chat_message = Fabricate(:chat_message, chat_channel: chat_channel, user: admin, use_service: true)
      chat_message.update!(created_at: chat_time)
      chat_channel.update!(last_message: chat_message)

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      payload = response.parsed_body["channels"].find { |channel| channel["id"] == public_channel.id }
      expect(Time.zone.parse(payload["last_activity_at"]).to_i).to eq(chat_time.to_i)
    end

    it "returns last activity only from surfaces enabled for the channel mode" do
      category_only_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Docs #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
        ).call
      chat_only_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Chat #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
        ).call
      category_only_channel.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_CHANNEL_MODE] = "category_only"
      category_only_channel.save_custom_fields(true)
      chat_only_channel.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_CHANNEL_MODE] = "chat_only"
      chat_only_channel.save_custom_fields(true)

      category_topic_time = 4.days.ago
      ignored_chat_time = 1.hour.ago
      ignored_topic_time = 30.minutes.ago
      chat_time = 2.days.ago
      Fabricate(:topic, category: category_only_channel, user: admin, bumped_at: category_topic_time)
      Fabricate(:topic, category: chat_only_channel, user: admin, bumped_at: ignored_topic_time)

      category_only_chat_channel = category_chat_channel(category_only_channel)
      ignored_chat_message =
        Fabricate(:chat_message, chat_channel: category_only_chat_channel, user: admin, use_service: true)
      ignored_chat_message.update!(created_at: ignored_chat_time)
      category_only_chat_channel.update!(last_message: ignored_chat_message)

      chat_only_chat_channel = category_chat_channel(chat_only_channel)
      chat_message = Fabricate(:chat_message, chat_channel: chat_only_chat_channel, user: admin, use_service: true)
      chat_message.update!(created_at: chat_time)
      chat_only_chat_channel.update!(last_message: chat_message)

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      category_payload =
        response.parsed_body["channels"].find { |channel| channel["id"] == category_only_channel.id }
      chat_payload = response.parsed_body["channels"].find { |channel| channel["id"] == chat_only_channel.id }
      expect(Time.zone.parse(category_payload["last_activity_at"]).to_i).to eq(category_topic_time.to_i)
      expect(Time.zone.parse(chat_payload["last_activity_at"]).to_i).to eq(chat_time.to_i)
    end

    it "returns workspace settings metadata for managers" do
      workspace.update_column(:description, "Shared [docs](https://example.com/workspace).")
      workspace.create_category_definition if workspace.topic.blank?
      public_channel
      private_channel
      workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_AUTO_JOIN_CHANNEL_IDS] = [
        public_channel.id,
        private_channel.id,
      ]
      workspace.save_custom_fields(true)

      sign_in(admin)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("workspace", "can_manage")).to eq(true)
      expect(response.parsed_body.dig("workspace", "public_read")).to eq(false)
      expect(response.parsed_body.dig("workspace", "members_can_create_channels")).to eq(true)
      expect(response.parsed_body.dig("workspace", "members_can_create_private_channels")).to eq(
        true,
      )
      expect(response.parsed_body.dig("workspace", "can_create_private_channel")).to eq(true)
      expect(response.parsed_body.dig("workspace", "about_raw")).to eq(
        "Shared [docs](https://example.com/workspace).",
      )
      expect(response.parsed_body.dig("workspace", "auto_join_channel_ids")).to eq(
        [public_channel.id, private_channel.id],
      )
      expect(response.parsed_body.dig("workspace", "auto_join_channel_options")).to include(
        include("id" => public_channel.id, "name" => public_channel.name, "visibility" => "public"),
        include(
          "id" => private_channel.id,
          "name" => private_channel.name,
          "visibility" => "private",
        ),
      )
    end

    it "hides private auto-join channels from workspace managers who cannot manage them" do
      workspace.workspace_group.group_users.find_by(user: workspace_member).update!(owner: true)
      public_channel
      private_channel
      workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_AUTO_JOIN_CHANNEL_IDS] = [
        public_channel.id,
        private_channel.id,
      ]
      workspace.save_custom_fields(true)

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("workspace", "can_manage")).to eq(true)
      expect(response.parsed_body.dig("workspace", "auto_join_channel_ids")).to eq(
        [public_channel.id],
      )
      expect(response.parsed_body.dig("workspace", "auto_join_channel_options")).to include(
        include("id" => public_channel.id, "name" => public_channel.name, "visibility" => "public"),
      )
      expect(response.parsed_body.dig("workspace", "auto_join_channel_options")).not_to include(
        include("id" => private_channel.id),
      )
    end
  end

  describe "#joinable_channel" do
    it "resolves a public channel category URL for workspace members who can join it" do
      public_channel

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channel.json", params: { path: public_channel.url }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "id")).to eq(public_channel.id)
      expect(response.parsed_body.dig("channel", "workspace_id")).to eq(workspace.id)
      expect(response.parsed_body.dig("channel", "can_join")).to eq(true)
    end

    it "resolves a topic URL inside a public channel for workspace members who can join it" do
      topic = Fabricate(:topic, category: public_channel, user: admin)

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channel.json", params: { path: topic.relative_url }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "id")).to eq(public_channel.id)
      expect(response.parsed_body.dig("channel", "can_join")).to eq(true)
    end

    it "resolves a chat URL inside a public channel for workspace members who can join it" do
      chat_channel = category_chat_channel(public_channel)

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channel.json", params: { path: chat_channel.url }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "id")).to eq(public_channel.id)
      expect(response.parsed_body.dig("channel", "can_join")).to eq(true)
    end

    it "resolves an already joined chat-only channel URL for redirecting to chat" do
      public_channel.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_CHANNEL_MODE] =
        DiscourseWorkspaceGroups::CHANNEL_MODE_CHAT_ONLY
      public_channel.save_custom_fields(true)
      public_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channel.json", params: { path: public_channel.url }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "id")).to eq(public_channel.id)
      expect(response.parsed_body.dig("channel", "joined")).to eq(true)
      expect(response.parsed_body.dig("channel", "can_join")).to eq(false)
      expect(response.parsed_body.dig("channel", "chat_channel_id")).to eq(
        category_chat_channel(public_channel).id,
      )
    end

    it "does not resolve private channels" do
      private_channel

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channel.json", params: { path: private_channel.url }

      expect(response).to have_http_status(:not_found)
    end

    it "does not resolve channels for non-workspace members" do
      public_channel

      sign_in(guest_user)
      get "/workspace-groups/joinable-channel.json", params: { path: public_channel.url }

      expect(response).to have_http_status(:not_found)
    end

    it "does not resolve channels the user has already joined" do
      public_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channel.json", params: { path: public_channel.url }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "#join_channel" do
    it "publishes a newly joined public chat channel only once" do
      public_channel

      sign_in(workspace_member)
      allow(Chat::Publisher).to receive(:publish_new_channel)

      post "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/membership.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "joined")).to eq(true)
      expect(Chat::Publisher).to have_received(:publish_new_channel).with(
        a_kind_of(Chat::Channel),
        [workspace_member.id],
      ).once
    end

    it "makes team owners channel owners when they join public channels" do
      public_channel
      workspace.workspace_group.group_users.find_by!(user: workspace_member).update!(owner: true)

      sign_in(workspace_member)

      post "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/membership.json"

      expect(response).to have_http_status(:ok)
      expect(public_channel.workspace_group.group_users.find_by!(user: workspace_member)).to be_owner
    end
  end

  describe "workspace group removal" do
    it "removes the member from workspace channels and paired chat memberships" do
      public_channel.workspace_group.add(workspace_member)
      private_channel.workspace_group.add(workspace_member)
      public_chat_channel = category_chat_channel(public_channel)
      private_chat_channel = category_chat_channel(private_channel)

      expect(public_chat_channel.membership_for(workspace_member)).to be_present
      expect(private_chat_channel.membership_for(workspace_member)).to be_present

      workspace.workspace_group.remove(workspace_member)

      expect(public_channel.workspace_group.users.exists?(id: workspace_member.id)).to eq(false)
      expect(private_channel.workspace_group.users.exists?(id: workspace_member.id)).to eq(false)
      expect(public_chat_channel.membership_for(workspace_member)).to be_nil
      expect(private_chat_channel.membership_for(workspace_member)).to be_nil
    end
  end

  describe "#archived_channels" do
    it "loads archived channels on demand" do
      archived_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Archive #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
        ).call
      DiscourseWorkspaceGroups::SetChannelArchiveState.new(
        channel: archived_channel,
        user: admin,
        archived: true,
      ).call

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}/archived-channels.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["channels"].map { |channel| channel["id"] }).to eq([archived_channel.id])
    end
  end

  describe "#chat_tracking" do
    it "returns native chat tracking for visible workspace chat channels" do
      chat_channel = category_chat_channel(public_channel)
      category_only_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Topics Only #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
          channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_CATEGORY_ONLY,
        ).call
      report = ::Chat::TrackingStateReport.new
      report.channel_tracking = {
        chat_channel.id => {
          unread_count: 2,
          mention_count: 1,
          watched_threads_unread_count: 0,
        },
      }

      allow(::Chat::TrackingStateReportQuery).to receive(:call).with(
        guardian: an_instance_of(Guardian),
        channel_ids: [chat_channel.id],
        include_missing_memberships: false,
        include_threads: false,
        include_read: false,
      ).and_return(report)

      sign_in(admin)
      get "/workspace-groups/workspaces/#{workspace.id}/chat-tracking.json"

      expect(response).to have_http_status(:ok)
      expect(::Chat::TrackingStateReportQuery).to have_received(:call).with(
        guardian: an_instance_of(Guardian),
        channel_ids: [chat_channel.id],
        include_missing_memberships: false,
        include_threads: false,
        include_read: false,
      )
      expect(response.parsed_body.dig("channel_tracking", chat_channel.id.to_s)).to eq(
        "unread_count" => 2,
        "mention_count" => 1,
        "watched_threads_unread_count" => 0,
      )
      expect(category_chat_channel(category_only_channel)).to be_nil
    end
  end

  describe "#joinable_channels" do
    it "finds public chat-enabled channels the workspace member can join" do
      chat_channel = category_chat_channel(public_channel)

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channels.json", params: { term: public_channel.name[0, 5] }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["channels"]).to contain_exactly(
        include(
          "id" => public_channel.id,
          "workspace_id" => workspace.id,
          "workspace_name" => workspace.name,
          "can_join" => true,
          "chat_channel_id" => chat_channel.id,
          "chat_channel_slug" => chat_channel.slug,
        ),
      )
    end

    it "does not find private, topic-only, already joined, or non-matching channels" do
      matching_public = public_channel
      non_matching_public =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Notes #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
        ).call
      topic_only_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "#{matching_public.name} Topics",
          description: nil,
          visibility: "public",
          channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_CATEGORY_ONLY,
        ).call
      private_channel.update!(name: "#{matching_public.name} Private")
      joined_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "#{matching_public.name} Joined",
          description: nil,
          visibility: "public",
        ).call
      joined_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channels.json", params: { term: matching_public.name }

      channel_ids = response.parsed_body["channels"].map { |channel| channel["id"] }
      expect(channel_ids).to contain_exactly(matching_public.id)
      expect(channel_ids).not_to include(
        non_matching_public.id,
        topic_only_channel.id,
        private_channel.id,
        joined_channel.id,
      )
    end

    it "does not find channels for non-workspace members" do
      public_channel

      sign_in(guest_user)
      get "/workspace-groups/joinable-channels.json", params: { term: public_channel.name }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["channels"]).to eq([])
    end

    it "returns an empty result for blank terms" do
      public_channel

      sign_in(workspace_member)
      get "/workspace-groups/joinable-channels.json", params: { term: " " }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["channels"]).to eq([])
    end
  end

  describe "#create_channel" do
    it "returns the created channel payload with paired chat data" do
      sign_in(admin)

      post "/workspace-groups/workspaces/#{workspace.id}/channels.json",
           params: {
             name: "Private Planning #{SecureRandom.hex(4)}",
             visibility: "private",
           }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "joined")).to eq(true)
      expect(response.parsed_body.dig("channel", "chat_channel", "id")).to be_present
      expect(
        response.parsed_body.dig("channel", "chat_channel", "current_user_membership", "following"),
      ).to eq(true)
    end

    it "creates category-only channels without paired chat payload" do
      sign_in(admin)

      post "/workspace-groups/workspaces/#{workspace.id}/channels.json",
           params: {
             name: "Topics Only #{SecureRandom.hex(4)}",
             visibility: "public",
             channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_CATEGORY_ONLY,
           }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "mode")).to eq(
        DiscourseWorkspaceGroups::CHANNEL_MODE_CATEGORY_ONLY,
      )
      expect(response.parsed_body.dig("channel", "chat_channel")).to be_nil
      expect(response.parsed_body.dig("channel", "chat_channel_id")).to be_nil
    end

    it "rejects private channel creation for ordinary members when disabled for the workspace" do
      workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_MEMBERS_CAN_CREATE_CHANNELS] = true
      workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_MEMBERS_CAN_CREATE_PRIVATE_CHANNELS] = false
      workspace.save_custom_fields(true)

      sign_in(workspace_member)

      post "/workspace-groups/workspaces/#{workspace.id}/channels.json",
           params: {
             name: "Member Private #{SecureRandom.hex(4)}",
             visibility: "private",
           }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "#update_channel" do
    it "updates the channel metadata and returns refreshed chat payload" do
      private_channel.workspace_group.add(workspace_member)

      sign_in(admin)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{private_channel.id}.json",
          params: {
            name: "Research Planning #{SecureRandom.hex(4)}",
            description: "Coordinate [notes](https://example.com/notes).",
            visibility: "public",
          }

      expect(response).to have_http_status(:ok)

      private_channel.reload
      expect(private_channel.name).to start_with("Research Planning")
      expect(private_channel.workspace_visibility).to eq("public")
      expect(private_channel.description_text).to eq("Coordinate notes.")
      expect(response.parsed_body.dig("channel", "description_cooked")).to include(
        "href=\"https://example.com/notes\"",
      )
      expect(response.parsed_body.dig("channel", "description_raw")).to eq(
        "Coordinate [notes](https://example.com/notes).",
      )
      expect(response.parsed_body.dig("channel", "visibility")).to eq("public")
      expect(response.parsed_body.dig("channel", "chat_channel", "id")).to eq(
        category_chat_channel(private_channel).id,
      )
    end

    it "can switch a channel into chat-only mode" do
      sign_in(admin)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: public_channel.name,
            description: public_channel.topic.first_post.raw,
            visibility: "public",
            channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_CHAT_ONLY,
          }

      expect(response).to have_http_status(:ok)

      public_channel.reload
      expect(public_channel.workspace_channel_mode).to eq(
        DiscourseWorkspaceGroups::CHANNEL_MODE_CHAT_ONLY,
      )
      expect(
        public_channel.category_groups.find_by(group_id: public_channel.workspace_group_id).permission_type,
      ).to eq(CategoryGroup.permission_types[:create_post])
      expect(response.parsed_body.dig("channel", "mode")).to eq(
        DiscourseWorkspaceGroups::CHANNEL_MODE_CHAT_ONLY,
      )
    end

    it "updates the paired chat channel-wide mention setting" do
      sign_in(admin)

      expect(category_chat_channel(public_channel).allow_channel_wide_mentions).to eq(true)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: public_channel.name,
            description: public_channel.topic.first_post.raw,
            visibility: "public",
            allow_channel_wide_mentions: false,
          }

      expect(response).to have_http_status(:ok)
      expect(category_chat_channel(public_channel).reload.allow_channel_wide_mentions).to eq(false)
      expect(response.parsed_body.dig("channel", "allow_channel_wide_mentions")).to eq(false)
    end

    it "marks a topics-enabled channel as an events channel" do
      sign_in(admin)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: public_channel.name,
            description: public_channel.topic.first_post.raw,
            visibility: "public",
            channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_BOTH,
            events_enabled: true,
          }

      expect(response).to have_http_status(:ok)
      expect(public_channel.reload.workspace_events_enabled?).to eq(true)
      expect(SiteSetting.events_calendar_categories.split("|")).to include(public_channel.id.to_s)
      expect(response.parsed_body.dig("channel", "events_enabled")).to eq(true)
    end

    it "removes event status when events are disabled" do
      sign_in(admin)
      SiteSetting.events_calendar_categories = public_channel.id.to_s

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: public_channel.name,
            description: public_channel.topic.first_post.raw,
            visibility: "public",
            channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_BOTH,
            events_enabled: false,
          }

      expect(response).to have_http_status(:ok)
      expect(public_channel.reload.workspace_events_enabled?).to eq(false)
      expect(SiteSetting.events_calendar_categories.split("|")).not_to include(public_channel.id.to_s)
      expect(response.parsed_body.dig("channel", "events_enabled")).to eq(false)
    end

    it "removes event status when switching to chat-only mode" do
      sign_in(admin)
      SiteSetting.events_calendar_categories = public_channel.id.to_s

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: public_channel.name,
            description: public_channel.topic.first_post.raw,
            visibility: "public",
            channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_CHAT_ONLY,
            events_enabled: true,
          }

      expect(response).to have_http_status(:ok)
      expect(public_channel.reload.workspace_channel_mode).to eq(
        DiscourseWorkspaceGroups::CHANNEL_MODE_CHAT_ONLY,
      )
      expect(public_channel.workspace_events_enabled?).to eq(false)
      expect(SiteSetting.events_calendar_categories.split("|")).not_to include(public_channel.id.to_s)
      expect(response.parsed_body.dig("channel", "events_enabled")).to eq(false)
    end

    it "updates category color and emoji style" do
      sign_in(admin)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: public_channel.name,
            description: public_channel.topic.first_post.raw,
            visibility: "public",
            color: "E45735",
            style_type: "emoji",
            emoji: "rocket",
          }

      expect(response).to have_http_status(:ok)

      public_channel.reload
      expect(public_channel.color).to eq("E45735")
      expect(public_channel.style_type).to eq("emoji")
      expect(public_channel.emoji).to eq("rocket")
      expect(response.parsed_body.dig("channel", "color")).to eq("E45735")
      expect(response.parsed_body.dig("channel", "style_type")).to eq("emoji")
      expect(response.parsed_body.dig("channel", "emoji")).to eq("rocket")
    end

    it "closes paired chat when switching a channel into category-only mode" do
      sign_in(admin)
      chat_channel = category_chat_channel(public_channel)
      expect(chat_channel).to be_present
      public_channel.workspace_group.add(workspace_member)
      DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: public_channel).call
      expect(
        Chat::UserChatChannelMembership.where(chat_channel_id: chat_channel.id).pluck(:user_id),
      ).to include(workspace_member.id)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: public_channel.name,
            description: public_channel.topic.first_post.raw,
            visibility: "public",
            channel_mode: DiscourseWorkspaceGroups::CHANNEL_MODE_CATEGORY_ONLY,
          }

      expect(response).to have_http_status(:ok)

      expect(public_channel.reload.workspace_channel_mode).to eq(
        DiscourseWorkspaceGroups::CHANNEL_MODE_CATEGORY_ONLY,
      )
      expect(chat_channel.reload.status).to eq("closed")
      expect(
        Chat::UserChatChannelMembership.where(chat_channel_id: chat_channel.id).pluck(:user_id),
      ).to include(workspace_member.id)
      expect(response.parsed_body.dig("channel", "chat_channel")).to be_nil
    end

    it "allows channel owners to update settings" do
      public_channel.workspace_group.add(workspace_member)
      public_channel.workspace_group.group_users.find_by(user: workspace_member).update!(owner: true)

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: "Member Managed #{SecureRandom.hex(4)}",
            description: "Owner-managed notes.",
            visibility: "public",
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "name")).to start_with("Member Managed")
      expect(response.parsed_body.dig("channel", "description")).to eq("Owner-managed notes.")
    end

    it "allows team owners to update public channel settings without joining the channel" do
      workspace.workspace_group.group_users.find_by(user: workspace_member).update!(owner: true)

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}.json",
          params: {
            name: "Team Managed #{SecureRandom.hex(4)}",
            description: "Team-managed notes.",
            visibility: "public",
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "name")).to start_with("Team Managed")
      expect(response.parsed_body.dig("channel", "description")).to eq("Team-managed notes.")
    end

    it "does not allow team owners to update private channel settings unless they own the channel" do
      workspace.workspace_group.group_users.find_by(user: workspace_member).update!(owner: true)

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/channels/#{private_channel.id}.json",
          params: {
            name: "Team Private #{SecureRandom.hex(4)}",
            description: "Private notes.",
            visibility: "private",
          }

      expect(response).to have_http_status(:forbidden)
    end

  end

  describe "#leave_channel" do
    it "removes a joined public channel membership and paired chat membership" do
      public_channel.workspace_group.add(workspace_member)
      chat_channel = category_chat_channel(public_channel)
      expect(chat_channel.membership_for(workspace_member)).to be_present

      sign_in(workspace_member)

      events =
        DiscourseEvent.track_events(:user_removed_from_group) do
          expect {
            delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/membership.json"
          }.to change { public_channel.workspace_group.users.exists?(id: workspace_member.id) }.from(true).to(false)
        end

      expect(response).to have_http_status(:ok)
      expect(events.map { |event| event[:params] }).to include([workspace_member, public_channel.workspace_group])
      expect(chat_channel.membership_for(workspace_member)).to be_nil
      expect(response.parsed_body.dig("channel", "joined")).to eq(false)
      expect(response.parsed_body.dig("channel", "can_join")).to eq(true)
      expect(response.parsed_body.dig("channel", "can_leave")).to eq(false)
    end

    it "removes membership from channels whose group grants trust" do
      Jobs.run_immediately!

      public_channel.workspace_group.add(workspace_member)
      public_channel.workspace_group.update!(grant_trust_level: TrustLevel[3])
      workspace_member.update!(trust_level: TrustLevel[3])

      sign_in(workspace_member)

      expect {
        delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/membership.json"
      }.to change { public_channel.workspace_group.users.exists?(id: workspace_member.id) }.from(true).to(false)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "joined")).to eq(false)
      expect(workspace_member.reload.trust_level).to be < TrustLevel[3]
    end

    it "leaves public chat-only channels without serializing a revoked category permission update" do
      chat_only_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Chat #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
          channel_mode: "chat_only",
        ).call
      chat_only_channel.workspace_group.add(workspace_member)
      chat_channel = category_chat_channel(chat_only_channel)
      expect(chat_channel.membership_for(workspace_member)).to be_present

      sign_in(workspace_member)

      expect {
        delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{chat_only_channel.id}/membership.json"
      }.to change { chat_only_channel.workspace_group.users.exists?(id: workspace_member.id) }.from(true).to(false)

      expect(response).to have_http_status(:ok)
      expect(chat_channel.membership_for(workspace_member)).to be_nil
      expect(response.parsed_body.dig("channel", "joined")).to eq(false)
      expect(response.parsed_body.dig("channel", "can_join")).to eq(true)
      expect(response.parsed_body.dig("channel", "can_leave")).to eq(false)
    end

    it "allows an admin channel owner to leave when another owner remains" do
      public_channel.workspace_group.add(workspace_member)
      public_channel.workspace_group.group_users.find_by!(user: workspace_member).update!(owner: true)

      sign_in(admin)

      expect {
        delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/membership.json"
      }.to change { public_channel.workspace_group.users.exists?(id: admin.id) }.from(true).to(false)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "joined")).to eq(false)
    end
  end

  describe "#update_sidebar_channels" do
    it "stores a per-user sidebar order for visible workspace channels" do
      first_public_channel = public_channel
      second_public_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Announcements #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
        ).call

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/sidebar-channels.json",
          params: {
            channel_ids: [second_public_channel.id, first_public_channel.id],
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["channel_ids"]).to eq(
        [second_public_channel.id, first_public_channel.id],
      )
      expect(
        DiscourseWorkspaceGroups.workspace_sidebar_orders_for(workspace_member.reload)[workspace.id.to_s],
      ).to eq([second_public_channel.id, first_public_channel.id])
    end

    it "rejects sidebar orders containing channels the user cannot see" do
      private_channel

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/sidebar-channels.json",
          params: {
            channel_ids: [private_channel.id],
          }

      expect(response).to have_http_status(:bad_request)
    end

    it "stores per-user sidebar sections and clears the old order for that workspace" do
      first_public_channel = public_channel
      second_public_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Papers #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
        ).call
      third_public_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Other #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
        ).call

      DiscourseWorkspaceGroups.persist_workspace_sidebar_orders!(
        workspace_member,
        workspace.id.to_s => [
          first_public_channel.id,
          second_public_channel.id,
          third_public_channel.id,
        ],
      )

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/sidebar-channels.json",
          params: {
            sections: [
              {
                id: "papers",
                title: "Papers",
                channel_ids: [second_public_channel.id],
                collapsed: true,
              },
              {
                id: "students",
                title: "Students",
                channel_ids: [first_public_channel.id],
              },
            ],
            other_channel_ids: [third_public_channel.id],
            other_collapsed: true,
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["sections"]["sections"]).to contain_exactly(
        include(
          "id" => "papers",
          "title" => "Papers",
          "channel_ids" => [second_public_channel.id],
          "collapsed" => true,
        ),
        include(
          "id" => "students",
          "title" => "Students",
          "channel_ids" => [first_public_channel.id],
          "collapsed" => false,
        ),
      )
      expect(response.parsed_body["sections"]["other_channel_ids"]).to eq([third_public_channel.id])
      expect(response.parsed_body["sections"]["other_collapsed"]).to eq(true)

      workspace_member.reload
      expect(
        DiscourseWorkspaceGroups.workspace_sidebar_sections_for(workspace_member)[workspace.id.to_s],
      ).to include(other_channel_ids: [third_public_channel.id], other_collapsed: true)
      expect(
        DiscourseWorkspaceGroups.workspace_sidebar_orders_for(workspace_member),
      ).not_to have_key(workspace.id.to_s)
    end

    it "preserves sidebar sections while pruning channels the user cannot see" do
      private_channel

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/sidebar-channels.json",
          params: {
            sections: [
              {
                id: "private",
                title: "Private",
                channel_ids: [private_channel.id],
              },
            ],
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["sections"]["sections"]).to contain_exactly(
        include("id" => "private", "title" => "Private", "channel_ids" => []),
      )
    end

    it "preserves sidebar sections while pruning archived channels" do
      public_channel.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_ARCHIVED] = true
      public_channel.save_custom_fields(true)

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/sidebar-channels.json",
          params: {
            sections: [
              {
                id: "archived",
                title: "Archived",
                channel_ids: [public_channel.id],
                collapsed: true,
              },
            ],
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["sections"]["sections"]).to contain_exactly(
        include("id" => "archived", "title" => "Archived", "channel_ids" => []),
      )
    end

    it "stores empty sidebar sections" do
      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}/sidebar-channels.json",
          params: {
            sections: [{ id: "new-group", title: "New group", channel_ids: [] }],
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["sections"]["sections"]).to contain_exactly(
        include("id" => "new-group", "title" => "New group", "channel_ids" => []),
      )
      expect(
        DiscourseWorkspaceGroups.workspace_sidebar_sections_for(workspace_member.reload)[workspace.id.to_s][
          :sections
        ],
      ).to contain_exactly(include(id: "new-group", title: "New group", channel_ids: []))
    end
  end

  describe "#archive_channel" do
    it "restores the chat status that existed before this plugin archived the channel" do
      sign_in(admin)
      chat_channel = category_chat_channel(public_channel)
      expect(chat_channel.status).to eq("open")

      post "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/archive.json"

      expect(response).to have_http_status(:ok)
      expect(chat_channel.reload.status).to eq("closed")

      delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/archive.json"

      expect(response).to have_http_status(:ok)
      expect(chat_channel.reload.status).to eq("open")
    end

    it "does not reopen an already active channel with an independently closed chat" do
      public_channel.workspace_group.add(workspace_member)
      public_channel.workspace_group.group_users.find_by(user: workspace_member).update!(owner: true)
      chat_channel = category_chat_channel(public_channel)
      chat_channel.update!(status: "closed")

      sign_in(workspace_member)

      delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/archive.json"

      expect(response).to have_http_status(:ok)
      expect(chat_channel.reload.status).to eq("closed")
    end

    it "preserves moderation changes made while the channel is archived" do
      sign_in(admin)
      chat_channel = category_chat_channel(public_channel)

      post "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/archive.json"
      expect(response).to have_http_status(:ok)
      chat_channel.update!(status: "read_only")

      delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/archive.json"

      expect(response).to have_http_status(:ok)
      expect(chat_channel.reload.status).to eq("read_only")
    end
  end

  describe "#update" do
    it "updates workspace description and permissions" do
      sign_in(admin)

      put "/workspace-groups/workspaces/#{workspace.id}.json",
          params: {
            description: "Team [handbook](https://example.com/handbook).",
            public_read: true,
            members_can_create_channels: false,
            members_can_create_private_channels: true,
          }

      expect(response).to have_http_status(:ok)

      workspace.reload
      expect(workspace.workspace_root_public_read?).to eq(true)
      expect(workspace.workspace_members_can_create_channels?).to eq(false)
      expect(workspace.workspace_members_can_create_private_channels?).to eq(false)
      expect(workspace.description_text).to eq("Team handbook.")
      expect(workspace.category_groups.find_by(group_id: Group::AUTO_GROUPS[:everyone]).permission_type).to eq(
        CategoryGroup.permission_types[:readonly],
      )
      expect(response.parsed_body.dig("workspace", "about_cooked")).to include(
        "href=\"https://example.com/handbook\"",
      )
      expect(response.parsed_body.dig("workspace", "members_can_create_private_channels")).to eq(
        false,
      )
    end

    it "updates workspace auto-join channels and enrolls existing workspace members" do
      public_channel
      expect(public_channel.workspace_group.users.exists?(id: workspace_member.id)).to eq(false)

      sign_in(admin)

      put "/workspace-groups/workspaces/#{workspace.id}.json",
          params: {
            description: "Workspace notes.",
            public_read: false,
            members_can_create_channels: true,
            members_can_create_private_channels: true,
            auto_join_channel_ids: [public_channel.id],
          }

      expect(response).to have_http_status(:ok)

      workspace.reload
      expect(workspace.workspace_auto_join_channel_ids).to eq([public_channel.id])
      expect(public_channel.workspace_group.users.exists?(id: workspace_member.id)).to eq(true)
      expect(response.parsed_body.dig("workspace", "auto_join_channel_ids")).to eq(
        [public_channel.id],
      )
    end

    it "accepts hash-style auto-join channel params from browser form payloads" do
      public_channel

      sign_in(admin)

      put "/workspace-groups/workspaces/#{workspace.id}.json",
          params: {
            description: "Workspace notes.",
            public_read: false,
            members_can_create_channels: true,
            members_can_create_private_channels: true,
            auto_join_channel_ids: {
              "0" => public_channel.id.to_s,
            },
          }

      expect(response).to have_http_status(:ok)

      workspace.reload
      expect(workspace.workspace_auto_join_channel_ids).to eq([public_channel.id])
      expect(response.parsed_body.dig("workspace", "auto_join_channel_ids")).to eq(
        [public_channel.id],
      )
    end

    it "rejects private auto-join channels that workspace managers cannot manage" do
      workspace.workspace_group.group_users.find_by(user: workspace_member).update!(owner: true)
      private_channel

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}.json",
          params: {
            description: "Workspace notes.",
            public_read: false,
            members_can_create_channels: true,
            members_can_create_private_channels: true,
            auto_join_channel_ids: [private_channel.id],
          }

      expect(response).to have_http_status(:bad_request)
      expect(workspace.reload.workspace_auto_join_channel_ids).to eq([])
      expect(private_channel.workspace_group.users.exists?(id: workspace_member.id)).to eq(false)
    end

    it "preserves private auto-join channels hidden from workspace managers" do
      workspace.workspace_group.group_users.find_by(user: workspace_member).update!(owner: true)
      public_channel
      private_channel
      workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_AUTO_JOIN_CHANNEL_IDS] = [
        private_channel.id,
      ]
      workspace.save_custom_fields(true)

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}.json",
          params: {
            description: "Workspace notes.",
            public_read: false,
            members_can_create_channels: true,
            members_can_create_private_channels: true,
            auto_join_channel_ids: [public_channel.id],
          }

      expect(response).to have_http_status(:ok)
      expect(workspace.reload.workspace_auto_join_channel_ids).to contain_exactly(
        public_channel.id,
        private_channel.id,
      )
      expect(response.parsed_body.dig("workspace", "auto_join_channel_ids")).to eq(
        [public_channel.id],
      )
    end

    it "allows workspace owners to update settings and removes member channel creation for non-managers" do
      workspace.workspace_group.add(workspace_member)
      workspace.workspace_group.group_users.find_by(user: workspace_member).update!(owner: true)

      sign_in(workspace_member)

      put "/workspace-groups/workspaces/#{workspace.id}.json",
          params: {
            description: "Owner-managed workspace notes.",
            public_read: false,
            members_can_create_channels: false,
            members_can_create_private_channels: false,
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("workspace", "can_manage")).to eq(true)
      expect(response.parsed_body.dig("workspace", "members_can_create_channels")).to eq(false)
      expect(response.parsed_body.dig("workspace", "members_can_create_private_channels")).to eq(
        false,
      )
      expect(response.parsed_body.dig("workspace", "can_create_channel")).to eq(true)
      expect(response.parsed_body.dig("workspace", "can_create_private_channel")).to eq(true)

      workspace.reload
      sign_in(guest_user)
      workspace.workspace_group.add(guest_user)
      get "/workspace-groups/workspaces/#{workspace.id}.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("workspace", "can_create_channel")).to eq(false)
      expect(response.parsed_body.dig("workspace", "can_create_private_channel")).to eq(false)
    end

    it "auto-joins newly added workspace members into configured channels" do
      public_channel
      workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_AUTO_JOIN_CHANNEL_IDS] = [public_channel.id]
      workspace.save_custom_fields(true)

      expect {
        workspace.workspace_group.add(guest_user)
      }.to change { public_channel.workspace_group.users.exists?(id: guest_user.id) }.from(false).to(true)
    end
  end

  describe "auto-join cleanup" do
    it "removes archived channels from the workspace auto-join list" do
      public_channel
      workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_AUTO_JOIN_CHANNEL_IDS] = [public_channel.id]
      workspace.save_custom_fields(true)

      DiscourseWorkspaceGroups::SetChannelArchiveState.new(
        channel: public_channel,
        user: admin,
        archived: true,
      ).call

      expect(workspace.reload.workspace_auto_join_channel_ids).to eq([])
    end
  end

  describe "#channel_access" do
    it "lists guests separately from team members" do
      private_channel.workspace_group.add(workspace_member)
      private_channel.workspace_group.add(guest_user)

      sign_in(admin)
      get "/workspace-groups/workspaces/#{workspace.id}/channels/#{private_channel.id}/access.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["members"]).to include(
        include("username" => workspace_member.username, "guest" => false),
        include("username" => guest_user.username, "guest" => true),
      )
    end

    it "allows public channel members to view access without removal controls" do
      public_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)
      get "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/access.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("channel", "can_add_members")).to eq(true)
      expect(response.parsed_body.dig("channel", "can_manage_members")).to eq(false)
      expect(response.parsed_body["members"]).to include(
        include("username" => workspace_member.username, "can_remove" => false),
      )
    end
  end

  describe "#add_channel_members" do
    it "adds direct guest access and syncs the paired chat membership" do
      private_channel

      sign_in(admin)

      expect {
        post "/workspace-groups/workspaces/#{workspace.id}/channels/#{private_channel.id}/access.json",
             params: {
               usernames: guest_user.username,
             }
      }.to change { private_channel.workspace_group.users.exists?(id: guest_user.id) }.from(false).to(true)

      expect(response).to have_http_status(:ok)
      expect(category_chat_channel(private_channel).membership_for(guest_user)).to be_present
      expect(response.parsed_body["members"].map { |member| member["username"] }).to include(
        guest_user.username,
      )
    end

    it "allows public channel members to add other team members" do
      public_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)

      expect {
        post "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/access.json",
             params: {
               usernames: other_workspace_member.username,
             }
      }.to change { public_channel.workspace_group.users.exists?(id: other_workspace_member.id) }.from(false).to(true)

      expect(response).to have_http_status(:ok)
      expect(category_chat_channel(public_channel).membership_for(other_workspace_member)).to be_present
      expect(response.parsed_body["members"].map { |member| member["username"] }).to include(
        other_workspace_member.username,
      )
    end

    it "rejects out-of-team users from public channel members" do
      public_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)

      expect {
        post "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/access.json",
             params: {
               usernames: guest_user.username,
             }
      }.not_to change { public_channel.workspace_group.users.exists?(id: guest_user.id) }

      expect(response).to have_http_status(:forbidden)
    end

    it "does not allow ordinary private channel members to add users" do
      private_channel.workspace_group.add(workspace_member)

      sign_in(workspace_member)

      expect {
        post "/workspace-groups/workspaces/#{workspace.id}/channels/#{private_channel.id}/access.json",
             params: {
               usernames: other_workspace_member.username,
             }
      }.not_to change { private_channel.workspace_group.users.exists?(id: other_workspace_member.id) }

      expect(response).to have_http_status(:forbidden)
    end

    it "returns a useful error for unknown usernames" do
      private_channel

      sign_in(admin)
      post "/workspace-groups/workspaces/#{workspace.id}/channels/#{private_channel.id}/access.json",
           params: {
             usernames: "missing-user",
           }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to include("Unknown users: missing-user")
    end
  end

  describe "#remove_channel_member" do
    it "removes direct guest access and drops the paired chat membership" do
      private_channel.workspace_group.add(guest_user)
      chat_channel = category_chat_channel(private_channel)
      expect(chat_channel.membership_for(guest_user)).to be_present

      sign_in(admin)

      allow(Chat::Publisher).to receive(:publish_kick_users).and_call_original

      expect {
        delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{private_channel.id}/access/#{guest_user.id}.json"
      }.to change { private_channel.workspace_group.users.exists?(id: guest_user.id) }.from(true).to(false)

      expect(response).to have_http_status(:ok)
      expect(chat_channel.membership_for(guest_user)).to be_nil
      expect(Chat::Publisher).to have_received(:publish_kick_users).with(
        chat_channel.id,
        [guest_user.id],
      )
    end

    it "removes members from chat-only channels without serializing revoked category updates" do
      chat_only_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: workspace,
          user: admin,
          name: "Access Chat #{SecureRandom.hex(4)}",
          description: nil,
          visibility: "public",
          channel_mode: "chat_only",
        ).call
      chat_only_channel.workspace_group.add(workspace_member)
      chat_channel = category_chat_channel(chat_only_channel)
      expect(chat_channel.membership_for(workspace_member)).to be_present

      sign_in(admin)

      expect {
        delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{chat_only_channel.id}/access/#{workspace_member.id}.json"
      }.to change { chat_only_channel.workspace_group.users.exists?(id: workspace_member.id) }.from(true).to(false)

      expect(response).to have_http_status(:ok)
      expect(chat_channel.membership_for(workspace_member)).to be_nil
    end
  end
end
