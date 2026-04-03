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
