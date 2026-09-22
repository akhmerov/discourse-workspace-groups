# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseWorkspaceGroups::VoiceController do
  fab!(:admin)
  fab!(:member) { Fabricate(:user, trust_level: 1) }
  fab!(:manager) { Fabricate(:user, trust_level: 2) }
  fab!(:outsider) { Fabricate(:user, trust_level: 2) }
  fab!(:other_admin, :admin)

  let(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(category: Fabricate(:category), user: admin).call
  end
  let(:channel) do
    DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace, user: admin, name: "Private research", description: "Private notes",
      visibility: "private", channel_mode: "category_only",
    ).call
  end
  let(:binding) do
    DiscourseWorkspaceGroups::VoiceBinding.create!(source_type: "category", source_id: channel.id, enabled: true)
  end
  let(:room) { binding.prepare!(member) }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.voice_enabled = true
    SiteSetting.voice_allowed_groups = Group::AUTO_GROUPS[:trust_level_2]
    SiteSetting.voice_direct_calls_allowed_groups = Group::AUTO_GROUPS[:trust_level_2]
    SiteSetting.voice_analytics_enabled = false
    channel.workspace_group.add(member)
    channel.workspace_group.group_users.create!(user: manager, owner: true)
  end

  def join_room(user, target = room)
    sign_in(user)
    post "/voice/rooms/#{target.id}/join.json"
    expect(response.status).to eq(200)
  end

  def invite_guest(user = outsider)
    join_room(manager)
    post "/voice/rooms/#{room.id}/invites.json", params: { usernames: [user.username] }
    expect(response.status).to eq(200)
  end

  it "admits TL1 channel members without changing trust or requiring chat mode" do
    binding
    sign_in(member)
    post "/workspace-groups/voice/prepare.json", params: { source_type: "category", source_id: channel.id }
    expect(response.status).to eq(200)
    expect(member.reload.trust_level).to eq(1)
    expect(channel.reload.workspace_channel_mode).to eq("category_only")
    expect(response.parsed_body.dig("room", "chat_channel_id")).to be_nil
    expect(Voice::RoomMembership.where(room_id: binding.reload.room_id).pluck(:user_id)).to eq([Discourse.system_user.id])
    join_room(member, binding.native_room)
  end

  it "rejects a TL2 outsider and nonparticipant staff on all native room access" do
    target = room
    [outsider, other_admin].each do |user|
      sign_in(user)
      get "/voice/rooms/#{target.id}.json"
      expect(response.status).to eq(403)
      post "/voice/rooms/#{target.id}/join.json"
      expect(response.status).to eq(403)
      get "/workspace-groups/voice/rooms.json"
      expect(response.parsed_body["channels"]).to be_empty
      post "/workspace-groups/voice/prepare.json", params: { source_type: "category", source_id: channel.id }
      expect(response.status).to eq(403)
    end
  end

  it "does not let workspace membership alone grant Town Square access" do
    workspace.workspace_group.add(outsider)
    expect(outsider.guardian.can_join_voice_room?(room)).to eq(false)
  end

  it "grants room access on channel join without entering a call or adding a second membership" do
    public_channel = DiscourseWorkspaceGroups::CreateChannel.new(
      workspace: workspace, user: admin, name: "Voice town square", description: "Voice discovery test", visibility: "public", channel_mode: "category_only",
    ).call
    public_binding = DiscourseWorkspaceGroups::VoiceBinding.create!(source_type: "category", source_id: public_channel.id, enabled: true)
    workspace.workspace_group.add(member)
    sign_in(member)
    notifications = MessageBus.track_publish("/workspace-voice/access/#{member.id}") do
      post "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/membership.json"
    end
    expect(response.status).to eq(200)
    expect(notifications).not_to be_empty
    expect(notifications.last.user_ids).to eq([member.id])
    get "/workspace-groups/voice/rooms.json"
    expect(response.parsed_body["channels"].map { |entry| entry["category_id"] }).to include(public_channel.id)
    expect(public_binding.reload.room_id).to be_nil
    target = public_binding.prepare!(member)
    expect(Voice::ParticipantTracker.user_ids(target.id)).to be_empty
    expect(Voice::RoomMembership.exists?(room_id: target.id, user_id: member.id)).to eq(false)
    notifications = MessageBus.track_publish("/workspace-voice/access/#{member.id}") do
      delete "/workspace-groups/workspaces/#{workspace.id}/channels/#{public_channel.id}/membership.json"
    end
    expect(response.status).to eq(200)
    expect(notifications).not_to be_empty
    get "/workspace-groups/voice/rooms.json"
    expect(response.parsed_body["channels"].map { |entry| entry["category_id"] }).not_to include(public_channel.id)
    expect(member.guardian.can_join_voice_room?(target)).to eq(false)
  end

  it "returns the same room on repeated preparation" do
    first = room.id
    expect(binding.prepare!(manager).id).to eq(first)
    expect(DiscourseWorkspaceGroups::VoiceBinding.where(source_id: channel.id).count).to eq(1)
  end

  it "resolves a stable room link after core expires an empty native room" do
    original = room
    slug = original.slug
    original.destroy!
    sign_in(outsider)
    get "/voice/rooms/#{slug}.json"
    expect(response.status).to eq(404)
    expect(binding.reload.room_id).to be_nil
    sign_in(member)
    get "/voice/rooms/#{slug}.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body.dig("room", "id")).not_to eq(original.id)
    expect(response.parsed_body.dig("room", "slug")).to eq(slug)
  end

  it "requires channel management to enable a room" do
    binding.update!(enabled: false)
    sign_in(member)
    put "/workspace-groups/workspaces/#{workspace.id}/channels/#{channel.id}.json", params: { name: channel.name, voice_enabled: true }
    expect(response.status).to eq(403)
    sign_in(manager)
    put "/workspace-groups/workspaces/#{workspace.id}/channels/#{channel.id}.json", params: { name: channel.name, voice_enabled: true }
    expect(response.status).to eq(200)
    expect(binding.reload.enabled).to eq(true)
  end

  it "blocks room and roster edits through native user and admin APIs" do
    target = room
    sign_in(manager)
    put "/voice/rooms/#{target.id}.json", params: { room: { public: true } }
    expect(response.status).to eq(403)
    post "/voice/rooms/#{target.id}/memberships.json", params: { user_id: outsider.id, role: "moderator" }
    expect(response.status).to eq(403)
    sign_in(other_admin)
    put "/admin/plugins/voice/rooms/#{target.id}.json", params: { room: { public: true } }
    expect(response.status).to eq(403)
    expect(target.reload.public).to eq(false)
    expect(outsider.guardian.can_join_voice_room?(target)).to eq(false)
  end

  it "removes active access and future broadcast delivery when group membership is removed" do
    join_room(member)
    channel.workspace_group.group_users.find_by!(user: member).destroy!
    expect(Voice::ParticipantTracker.user_ids(room.id)).not_to include(member.id)
    expect(room.message_bus_targets[:user_ids]).not_to include(member.id)
    post "/voice/rooms/#{room.id}/heartbeat.json"
    expect(response.status).to eq(403)
  end

  it "ends the active session when channel Voice is disabled" do
    join_room(member)
    sign_in(manager)
    put "/workspace-groups/workspaces/#{workspace.id}/channels/#{channel.id}.json", params: { name: channel.name, voice_enabled: false }
    expect(response.status).to eq(200)
    expect(Voice::ParticipantTracker.user_ids(room.id)).to be_empty
    expect(member.guardian.can_join_voice_room?(room)).to eq(false)
  end

  it "ends the active session on archive and uses current membership on unarchive" do
    join_room(member)
    DiscourseWorkspaceGroups::SetChannelArchiveState.new(channel: channel, user: manager, archived: true).call
    expect(Voice::ParticipantTracker.user_ids(room.id)).to be_empty
    expect(member.guardian.can_join_voice_room?(room)).to eq(false)
    DiscourseWorkspaceGroups::SetChannelArchiveState.new(channel: channel, user: manager, archived: false).call
    expect(member.guardian.can_join_voice_room?(room)).to eq(true)
  end

  it "revokes an active suspended participant" do
    join_room(member)
    member.update!(suspended_till: 1.day.from_now)
    expect(Voice::ParticipantTracker.user_ids(room.id)).not_to include(member.id)
    expect(member.guardian.can_join_voice_room?(room)).to eq(false)
  end

  it "fails closed when the plugin is disabled" do
    join_room(member)
    SiteSetting.discourse_workspace_groups_enabled = false
    expect(member.guardian.can_join_voice_room?(room)).to eq(false)
    expect(Voice::ParticipantTracker.user_ids(room.id)).to be_empty
  end

  it "admits a temporary guest without channel or native room membership" do
    invite_guest
    expect(binding.guest_grants.exists?(user_id: outsider.id)).to eq(true)
    expect(channel.workspace_group.users.exists?(outsider.id)).to eq(false)
    expect(Voice::RoomMembership.exists?(room_id: room.id, user_id: outsider.id)).to eq(false)
    join_room(outsider)
    expect(response.parsed_body.dig("room", "workspace_voice", "is_guest")).to eq(true)
    expect(response.parsed_body.dig("room", "workspace_voice", "conversation_url")).to be_nil
    expect(outsider.guardian.can_see_category?(channel)).to eq(false)
    get "/workspace-groups/voice/rooms.json"
    expect(response.parsed_body["channels"]).to be_empty
  end

  it "prevents members from admitting outsiders and guests from inviting others" do
    join_room(member)
    post "/voice/rooms/#{room.id}/invites.json", params: { usernames: [outsider.username] }
    expect(response.status).to eq(200)
    expect(binding.guest_grants.count).to eq(0)
    invite_guest
    join_room(outsider)
    post "/voice/rooms/#{room.id}/invites.json", params: { usernames: [other_admin.username] }
    expect(response.status).to eq(403)
  end

  it "does not admit or notify a visitor who blocks the inviter" do
    outsider.user_option.update!(allow_private_messages: false)
    invite_guest
    expect(binding.guest_grants.exists?(user_id: outsider.id)).to eq(false)
    expect(Voice::Invite.exists?(room_id: room.id, user_id: outsider.id)).to eq(false)
  end

  it "revokes guests and clears call messages when the last regular participant leaves" do
    invite_guest
    join_room(outsider)
    post "/workspace-groups/voice/rooms/#{room.id}/messages.json", params: { text: "https://example.org/paper" }
    expect(response.status).to eq(200)
    sign_in(manager)
    delete "/voice/rooms/#{room.id}/leave.json"
    expect(response.status).to eq(204)
    expect(binding.guest_grants.count).to eq(0)
    expect(Voice::ParticipantTracker.user_ids(room.id)).to be_empty
    expect(Discourse.redis.llen(binding.messages_key)).to eq(0)
    expect(outsider.guardian.can_join_voice_room?(room)).to eq(false)
  end

  it "limits guest messages to the current session after admission" do
    join_room(manager)
    binding.add_message!(manager, "Earlier member-only discussion")
    freeze_time 1.second.from_now.change(usec: 0)
    post "/voice/rooms/#{room.id}/invites.json", params: { usernames: [outsider.username] }
    join_room(outsider)
    post "/workspace-groups/voice/rooms/#{room.id}/messages.json", params: { text: "Guest's link" }
    expect(response.status).to eq(200)
    get "/workspace-groups/voice/rooms/#{room.id}/messages.json"
    expect(response.parsed_body["messages"].map { |message| message["text"] }).to eq(["Guest's link"])
    sign_in(member)
    get "/workspace-groups/voice/rooms/#{room.id}/messages.json"
    expect(response.status).to eq(403)
  end

  it "lets a manager disable temporary guests and immediately revoke existing ones" do
    invite_guest
    join_room(outsider)
    sign_in(manager)
    put "/workspace-groups/workspaces/#{workspace.id}/channels/#{channel.id}.json", params: { name: channel.name, voice_allow_guests: false }
    expect(response.status).to eq(200)
    expect(binding.reload.allow_guests).to eq(false)
    expect(Voice::ParticipantTracker.user_ids(room.id)).not_to include(outsider.id)
    post "/voice/rooms/#{room.id}/invites.json", params: { usernames: [outsider.username] }
    expect(binding.guest_grants.where(user: outsider)).not_to exist
    expect(outsider.guardian.can_join_voice_room?(room)).to eq(false)
  end

  it "revokes a kicked guest until a manager admits them again" do
    invite_guest
    join_room(outsider)
    sign_in(manager)
    delete "/voice/rooms/#{room.id}/kick.json", params: { user_id: outsider.id }
    expect(response.status).to eq(204)
    expect(binding.guest_grants.where(user: outsider)).not_to exist
    expect(outsider.guardian.can_join_voice_room?(room)).to eq(false)
  end

  it "does not erase media metadata when publishing guest and role labels" do
    join_room(member)
    metadata = Voice::ParticipantTracker.get_metadata(room.id, member.id).merge(is_muted: true, is_video_enabled: true)
    Voice::ParticipantTracker.update_metadata(room.id, member.id, metadata)
    Voice::RoomBroadcaster.publish_participants(room)
    result = Voice::ParticipantTracker.get_metadata(room.id, member.id)
    expect(result[:is_muted]).to eq(true)
    expect(result[:is_video_enabled]).to eq(true)
  end

  it "rejects a message writer whose session has ended" do
    join_room(manager)
    binding.reconcile!(end_session: true)
    expect { binding.add_message!(manager, "Late message") }.to raise_error(Discourse::InvalidAccess)
    expect(Discourse.redis.llen(binding.messages_key)).to eq(0)
  end

  it "does not restore a suspended guest grant after reinstatement" do
    invite_guest
    outsider.update!(suspended_till: 1.day.from_now)
    outsider.update!(suspended_till: nil)
    expect(binding.guest_grants.where(user: outsider)).not_to exist
    expect(outsider.guardian.can_join_voice_room?(room)).to eq(false)
  end

  it "leaves ordinary native direct-call authorization unchanged" do
    native = Fabricate(:voice_room, creator: outsider, public: false)
    expect(member.guardian.can_access_voice?).to eq(false)
    expect(member.guardian.can_join_voice_room?(native)).to eq(false)
    expect(outsider.guardian.can_join_voice_room?(native)).to eq(true)
  end

  context "with a group DM" do
    let(:dm) { Fabricate(:direct_message_channel) }

    before do
      dm.direct_message.update!(group: true)
      dm.direct_message.users = [manager, member]
    end

    it "binds to exact DM participants, excluding workspace owners and other staff" do
      sign_in(manager)
      post "/workspace-groups/voice/prepare.json", params: { source_type: "dm", source_id: dm.id }
      expect(response.status).to eq(200)
      target = Voice::Room.find(response.parsed_body.dig("room", "id"))
      expect(member.guardian.can_join_voice_room?(target)).to eq(false)
      join_room(manager, target)
      expect(member.guardian.can_join_voice_room?(target)).to eq(true)
      expect(other_admin.guardian.can_join_voice_room?(target)).to eq(false)
      expect(admin.guardian.can_join_voice_room?(target)).to eq(false)
      get "/workspace-groups/voice/rooms.json"
      expect(response.parsed_body["channels"].map { |entry| entry.dig("room", "id") }).not_to include(target.id)
      dm.direct_message.users.delete(member)
      expect(member.guardian.can_join_voice_room?(target)).to eq(false)
    end

    it "revokes an active participant immediately when they leave the group DM" do
      target = DiscourseWorkspaceGroups::VoiceBinding.new(source_type: "dm", source_id: dm.id, enabled: true).prepare!(manager)
      join_room(manager, target)
      join_room(member, target)
      dm.leave(member)
      expect(Voice::ParticipantTracker.user_ids(target.id)).not_to include(member.id)
    end

    it "rejects restarting an empty DM through the native join endpoint" do
      target = DiscourseWorkspaceGroups::VoiceBinding.new(source_type: "dm", source_id: dm.id, enabled: true).prepare!(manager)
      sign_in(member)
      post "/voice/rooms/#{target.id}/join.json"
      expect(response.status).to eq(403)
      get "/workspace-groups/voice/dms/#{dm.id}.json"
      expect(response.parsed_body["can_call"]).to eq(false)
      join_room(manager, target)
      sign_in(member)
      get "/workspace-groups/voice/dms/#{dm.id}.json"
      expect(response.parsed_body["can_call"]).to eq(true)
    end

    it "keeps the direct-call start gate for TL1 users" do
      sign_in(member)
      post "/workspace-groups/voice/prepare.json", params: { source_type: "dm", source_id: dm.id }
      expect(response.status).to eq(403)
    end
  end
end
