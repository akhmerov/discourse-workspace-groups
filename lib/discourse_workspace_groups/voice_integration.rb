# frozen_string_literal: true

module DiscourseWorkspaceGroups
  module VoiceIntegration
    def self.binding(room)
      VoiceBinding.find_by(room_id: room.id) if room
    end

    module GuardianPermissions
      def can_join_voice_room?(room)
        binding = VoiceIntegration.binding(room)
        binding ? binding.can_join?(user) : super
      end

      def can_see_voice_room?(room)
        binding = VoiceIntegration.binding(room)
        binding ? binding.can_join?(user) : super
      end

      def can_manage_voice_room?(room)
        binding = VoiceIntegration.binding(room)
        binding ? binding.can_manage?(user) : super
      end

      def can_invite_to_voice_room?(room)
        binding = VoiceIntegration.binding(room)
        binding ? (binding.available? && binding.member?(user)) : super
      end
    end

    module RoomAudience
      def member_ids
        binding = VoiceIntegration.binding(self)
        binding ? binding.audience_ids : super
      end

      def message_bus_targets
        binding = VoiceIntegration.binding(self)
        # MessageBus forbids an empty user_ids array. -1 is the system user;
        # ordinary clients cannot subscribe as that identity.
        binding ? { user_ids: binding.audience_ids.presence || [-1] } : super
      end
    end

    module RoomBroadcasts
      def publish_participants(...)
        if (binding = VoiceIntegration.binding(room))
          binding.reconcile!
          ::Voice::ParticipantTracker.list(room.id).each do |user|
            metadata = ::Voice::ParticipantTracker.get_metadata(room.id, user.id)
            metadata[:workspace_voice_guest] = !binding.member?(user)
            metadata[:role] = binding.can_manage?(user) ? "moderator" : "participant"
            ::Voice::ParticipantTracker.update_metadata(room.id, user.id, metadata)
          end
        end
        super
      end

      private

      def room_message_bus_targets
        binding = VoiceIntegration.binding(room)
        binding ? room.message_bus_targets : super
      end
    end

    module ManagedInvites
      def invite!
        binding = VoiceIntegration.binding(@room)
        return super unless binding
        return unless binding.available? && binding.member?(@inviter)
        return if @user.id == @inviter.id || @user.bot?
        unless binding.can_join?(@user)
          return unless binding.allow_guests? && binding.source_type == "category" && binding.can_manage?(@inviter)
          return if notifications_blocked?
          return unless binding.invite_guest!(@inviter, @user)
        end
        # Native private invites create a membership before checking access.
        # Managed rooms never grant independent native membership.
        invite = ::Voice::Invite.create_or_find_by!(
          room_id: @room.id, user_id: @user.id, invited_by_id: @inviter.id,
        ) { |record| record.source = ::Voice::Invite::SOURCES[:notification] }
        notify!(invite) if should_notify?(invite)
        @user
      end
    end

    module ManagedRoomRequests
      def join
        binding = VoiceIntegration.binding(@room)
        return super unless binding
        binding.with_lock { super }
      end

      def leave
        binding = VoiceIntegration.binding(@room)
        # A revoked client may finish its native leave request after removal.
        # It has nothing left to mutate; acknowledge that teardown idempotently.
        return head :no_content if binding && !binding.can_join?(current_user)
        super
      end

      def kick
        binding = VoiceIntegration.binding(@room)
        if binding
          guardian.ensure_can_manage_voice_room!(@room)
          binding.guest_grants.where(user_id: params.require(:user_id)).delete_all
        end
        super
      end

      private

      def load_room
        # Core expires empty ephemeral rooms. A channel's shared URL still
        # resolves to its place; guests must be admitted again for a new call.
        match = /\Aworkspace-(category|dm)-(\d+)\z/.match(params[:id].to_s)
        if match
          binding = VoiceBinding.find_by(source_type: match[1], source_id: match[2])
          binding.prepare!(current_user) if binding&.can_join?(current_user) && !binding.native_room
        end
        super
      end

      def check_workspace_voice_binding
        binding = VoiceIntegration.binding(@room)
        return unless binding
        if %w[update destroy start_recording stop_recording].include?(action_name)
          raise Discourse::InvalidAccess
        end
        binding.reconcile!
      end
    end

    module ManagedMembershipRequests
      private

      def check_workspace_voice_membership
        raise Discourse::InvalidAccess if VoiceIntegration.binding(@room)
      end
    end

    module DirectMessageDeparture
      def leave(user)
        result = super
        VoiceBinding.find_by(source_type: "dm", source_id: id)&.reconcile!
        result
      end
    end

    module ParticipantRemoval
      def remove(room_id, user_id)
        super
        return if Thread.current[:workspace_voice_reconciling]
        binding = VoiceBinding.find_by(room_id: room_id)
        return unless binding && !binding.session_active?
        begin
          Thread.current[:workspace_voice_reconciling] = true
          binding.reconcile!
        ensure
          Thread.current[:workspace_voice_reconciling] = false
        end
      end
    end

    module AdminRoomRequests
      def index
        rooms = ::Voice::Room.where.not(id: VoiceBinding.where.not(room_id: nil).select(:room_id))
        render_serialized rooms.includes(:creator, :room_memberships).order(:name), ::Voice::AdminRoomSerializer, root: :rooms
      end

      def end_call
        binding = VoiceBinding.find_by(room_id: params[:id])
        return super unless binding
        binding.reconcile!(end_session: true)
        head :no_content
      end

      private

      def check_workspace_voice_admin_room
        binding = VoiceBinding.find_by(room_id: params[:id])
        return unless binding
        raise Discourse::InvalidAccess if action_name != "end_call"
      end
    end

    module RoomDetails
      def can_invite
        VoiceIntegration.binding(object) ? false : super
      end

      def member_count
        binding = VoiceIntegration.binding(object)
        binding ? binding.audience_ids.length : super
      end

      def workspace_voice
        binding = VoiceIntegration.binding(object)
        return unless binding && binding.can_join?(scope.user)
        {
          binding_id: binding.id,
          source_type: binding.source_type,
          source_id: binding.source_id,
          conversation_url: binding.member?(scope.user) ? binding.conversation_url : nil,
          audience: binding.source_type == "category" ? binding.source.name : I18n.t("discourse_workspace_groups.voice.dm_audience"),
          guest_user_ids: binding.guest_grants.pluck(:user_id) & ::Voice::ParticipantTracker.user_ids(object.id),
          is_guest: !binding.member?(scope.user),
          can_admit_guests: binding.allow_guests? && binding.source_type == "category" && binding.can_manage?(scope.user),
          allow_guests: binding.allow_guests?,
        }
      end
    end
  end
end
