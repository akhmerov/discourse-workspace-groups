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
      expect(response.parsed_body["channels"].map { |channel| channel["id"] }).to eq([private_channel.id])
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
        include("id" => private_channel.id, "name" => private_channel.name, "visibility" => "private"),
      )
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
      expect(response.parsed_body.dig("workspace", "auto_join_channel_ids")).to eq([public_channel.id])
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
      expect(response.parsed_body.dig("workspace", "auto_join_channel_ids")).to eq([public_channel.id])
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

      sign_in(admin)

      expect {
        delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{private_channel.id}/access/#{guest_user.id}.json"
      }.to change { private_channel.workspace_group.users.exists?(id: guest_user.id) }.from(true).to(false)

      expect(response).to have_http_status(:ok)
      expect(category_chat_channel(private_channel).membership_for(guest_user)).to be_nil
    end
  end
end
