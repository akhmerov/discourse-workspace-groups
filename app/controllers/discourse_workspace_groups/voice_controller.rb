# frozen_string_literal: true

module DiscourseWorkspaceGroups
  class VoiceController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login
    before_action :ensure_voice_enabled

    skip_before_action :check_xhr, only: :page

    def page
      render "default/empty"
    end

    # Lists calls in progress in the user's channels; idle channels have nothing to show.
    def index
      channel_ids =
        CategoryCustomField.where(
          name: DiscourseWorkspaceGroups::WORKSPACE_GROUP_ID,
          value: current_user.group_users.pluck(:group_id).map(&:to_s),
        ).select(:category_id)
      bindings = VoiceBinding.where(source_type: "category", enabled: true, source_id: channel_ids)
      entries = VoiceBinding.occupied(bindings).filter_map do |binding|
        next unless binding.can_join?(current_user) && binding.member?(current_user)
        channel = binding.source
        room = binding.native_room
        {
          category_id: channel.id,
          name: channel.name,
          workspace_id: channel.workspace_parent_category.id,
          workspace_name: channel.workspace_parent_category.name,
          room: room ? serialize_room(room) : nil,
        }
      end
      render json: { channels: entries }
    end

    def dm_status
      binding = VoiceBinding.find_or_initialize_by(source_type: "dm", source_id: params.require(:source_id))
      binding.enabled = true if binding.new_record?
      raise Discourse::InvalidAccess unless binding.available? && binding.member?(current_user)
      binding.reconcile! if binding.persisted?
      render json: { can_call: binding.can_join?(current_user), active: binding.session_active? }
    end

    def prepare
      source_type = params.require(:source_type).to_s
      raise Discourse::InvalidParameters.new(:source_type) if %w[category dm].exclude?(source_type)
      source_id = params.require(:source_id).to_i
      binding = VoiceBinding.find_by(source_type: source_type, source_id: source_id)
      # Calls start on demand; a binding only records a channel's opt-out and its live room.
      binding ||= VoiceBinding.new(source_type: source_type, source_id: source_id, enabled: true)
      raise Discourse::InvalidAccess unless binding&.can_join?(current_user)
      RateLimiter.new(current_user, "workspace-voice-prepare", 30, 1.minute).performed!
      room = nil
      DistributedMutex.synchronize("workspace-voice-#{source_type}-#{source_id}") do
        binding = VoiceBinding.find_by(source_type: source_type, source_id: source_id) || binding
        room = binding.prepare!(current_user)
      end
      render json: {
        room: serialize_room(room),
        conversation_url: binding.member?(current_user) ? binding.conversation_url : nil,
        audience: source_type == "category" ? binding.source.name : I18n.t("discourse_workspace_groups.voice.dm_audience"),
      }
    end

    def ring
      binding = VoiceBinding.find_by!(room_id: params.require(:room_id))
      raise Discourse::InvalidAccess unless binding.source_type == "dm" && binding.can_join?(current_user)
      raise Discourse::InvalidAccess unless guardian.can_start_voice_call?
      room = binding.native_room
      raise Discourse::InvalidAccess unless room && ::Voice::ParticipantTracker.participant_session?(room.id, current_user.id)
      RateLimiter.new(current_user, "workspace-voice-ring", 3, 1.minute).performed!
      users = User.where(id: binding.audience_ids - ::Voice::ParticipantTracker.user_ids(room.id))
      ::Voice::RoomInviter.invite!(room: room, inviter: current_user, users: users)
      render json: success_json
    end

    def messages
      binding = participant_binding
      render json: { messages: binding.messages_for(current_user) }
    end

    def create_message
      binding = participant_binding
      RateLimiter.new(current_user, "workspace-voice-messages", 20, 1.minute).performed!
      render json: { message: binding.add_message!(current_user, params.require(:text).to_s.strip) }
    end

    def end_session
      binding = VoiceBinding.find_by!(room_id: params.require(:room_id))
      raise Discourse::InvalidAccess unless binding.can_manage?(current_user)
      binding.reconcile!(end_session: true)
      render json: success_json
    end

    private

    def ensure_voice_enabled
      raise Discourse::InvalidAccess unless VoiceBinding.integration_enabled?
    end

    def participant_binding
      binding = VoiceBinding.find_by!(room_id: params.require(:room_id))
      binding.reconcile!
      unless binding.can_join?(current_user) && ::Voice::ParticipantTracker.participant_session?(binding.room_id, current_user.id)
        raise Discourse::InvalidAccess
      end
      binding
    end

    def serialize_room(room)
      ::Voice::RoomSerializer.new(room, scope: guardian, root: false).as_json
    end
  end
end
