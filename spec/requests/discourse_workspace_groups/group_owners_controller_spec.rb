# frozen_string_literal: true

RSpec.describe GroupsController do
  fab!(:admin)
  fab!(:user)
  fab!(:category)

  let(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call
  end

  let(:public_channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Public research",
      description: nil,
      visibility: "public",
    ).call
  end

  let(:private_channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace,
      user: admin,
      name: "Private research",
      description: nil,
      visibility: "private",
    ).call
  end

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
  end

  describe "#add_owners" do
    it "promotes existing channel members with their team role" do
      workspace.workspace_group.add(user)
      public_channel.workspace_group.add(user)
      private_channel.workspace_group.add(user)
      sign_in(admin)

      put "/groups/#{workspace.workspace_group.id}/owners.json", params: { user_id: user.id }

      expect(response).to have_http_status(:ok)
      expect(public_channel.workspace_group.group_users.find_by!(user: user)).to be_owner
      expect(private_channel.workspace_group.group_users.find_by!(user: user)).to be_owner
      expect(user.reload.trust_level).to eq(DiscourseWorkspaceGroups::TEAM_OWNER_TRUST_LEVEL)
    end

    it "leaves channels the new owner has not joined untouched" do
      workspace.workspace_group.add(user)
      public_channel
      private_channel
      sign_in(admin)

      put "/groups/#{workspace.workspace_group.id}/owners.json", params: { user_id: user.id }

      expect(response).to have_http_status(:ok)
      expect(public_channel.workspace_group.group_users.where(user: user)).not_to exist
      expect(private_channel.workspace_group.group_users.where(user: user)).not_to exist
    end

    it "rejects self-promotion by an ordinary team member" do
      workspace.workspace_group.add(user)
      private_channel.workspace_group.add(user)
      sign_in(user)

      put "/groups/#{workspace.workspace_group.id}/owners.json", params: { user_id: user.id }

      expect(response).to have_http_status(:forbidden)
      expect(private_channel.workspace_group.group_users.find_by!(user: user)).not_to be_owner
    end
  end

  describe "membership ownership changes" do
    it "preserves trust levels when adding ordinary members" do
      user.update!(trust_level: TrustLevel[2])

      workspace.workspace_group.add(user)

      expect(user.reload.trust_level).to eq(TrustLevel[2])
    end

    it "promotes joined channels including archived channels" do
      workspace.workspace_group.add(user)
      public_channel.workspace_group.add(user)
      private_channel.workspace_group.add(user)
      DiscourseWorkspaceGroups::SetChannelArchiveState.new(
        channel: private_channel,
        user: admin,
        archived: true,
      ).call

      workspace.workspace_group.group_users.find_by!(user: user).update!(owner: true)

      expect(public_channel.workspace_group.group_users.find_by!(user: user)).to be_owner
      expect(private_channel.workspace_group.group_users.find_by!(user: user)).to be_owner
    end

    it "promotes a channel guest when creating a team owner" do
      private_channel.workspace_group.add(user)

      workspace.workspace_group.add_owner(user)

      expect(private_channel.workspace_group.group_users.find_by!(user: user)).to be_owner
    end

    it "promotes team owners when added to private channels" do
      workspace.workspace_group.add_owner(user)

      private_channel.workspace_group.add(user)

      expect(private_channel.workspace_group.group_users.find_by!(user: user)).to be_owner
    end

    it "keeps other teams' memberships unchanged" do
      workspace.workspace_group.add(user)
      other_workspace =
        DiscourseWorkspaceGroups::EnsureWorkspace.new(
          category: Fabricate(:category),
          user: admin,
        ).call
      other_channel =
        DiscourseWorkspaceGroups::CreateChannel.new(
          workspace: other_workspace,
          user: admin,
          name: "Other team research",
          description: nil,
          visibility: "private",
        ).call
      other_channel.workspace_group.add(user)

      workspace.workspace_group.group_users.find_by!(user: user).update!(owner: true)

      expect(other_channel.workspace_group.group_users.find_by!(user: user)).not_to be_owner
    end
  end
end
