# frozen_string_literal: true

module DiscourseWorkspaceGroups
  # This records a conversation binding, never a second membership roster.
  # Native rooms are private, system-owned and ephemeral, so ordinary users
  # retain no native membership if the integration is removed.
  class VoiceBinding < ActiveRecord::Base
    self.table_name = "workspace_voice_bindings"

    has_many :guest_grants, class_name: "DiscourseWorkspaceGroups::VoiceGuestGrant", dependent: :delete_all

    validates :source_type, inclusion: { in: %w[category dm] }
    validates :source_id, presence: true, uniqueness: { scope: :source_type }

    def self.integration_enabled?
      SiteSetting.discourse_workspace_groups_enabled && defined?(::Voice::Room) &&
        SiteSetting.voice_enabled
    end

    def self.account_eligible?(user)
      user.present? && user.id.positive? && user.active? && !user.staged? &&
        !user.suspended? && !user.silenced?
    end

    def source
      if source_type == "category"
        Category.find_by(id: source_id)
      else
        ::Chat::DirectMessageChannel.find_by(id: source_id)
      end
    end

    def available?
      return false unless self.class.integration_enabled? && enabled?
      item = source
      if source_type == "category"
        item&.workspace_channel? && !item.workspace_archived? &&
          item.workspace_parent_category&.workspace_root?
      else
        SiteSetting.chat_enabled && item.present? && item.open? && item.deleted_at.nil?
      end
    end

    def regular_user_ids
      item = source
      return [] unless item
      if source_type == "category"
        GroupUser.where(group_id: item.workspace_group_id).pluck(:user_id)
      else
        item.direct_message.direct_message_users.pluck(:user_id)
      end
    end

    def member?(user)
      return false unless self.class.account_eligible?(user)
      if source_type == "category"
        item = source
        item.present? && GroupUser.exists?(group_id: item.workspace_group_id, user_id: user.id)
      else
        item = source
        item.present? && item.direct_message.direct_message_users.exists?(user_id: user.id) &&
          user.guardian.can_chat? && user.user_option.chat_enabled
      end
    end

    def can_join?(user)
      return false unless available? && self.class.account_eligible?(user)
      return false unless member?(user) || guest?(user)
      source_type != "dm" || session_active? || user.guardian.can_start_voice_call?
    end

    def can_manage?(user)
      return false unless available? && member?(user)
      source_type == "dm" || DiscourseWorkspaceGroups.can_manage_workspace_channel?(source, user)
    end

    def audience_ids
      return [] unless available?
      ids = regular_user_ids
      ids += guest_grants.pluck(:user_id) if allow_guests? && session_active?
      User.where(id: ids).select do |user|
        self.class.account_eligible?(user) && (source_type == "category" || member?(user))
      end.map(&:id)
    end

    def session_active?
      room_id.present? && (::Voice::ParticipantTracker.user_ids(room_id) & regular_user_ids).any?
    end

    def guest?(user)
      allow_guests? && source_type == "category" && user.present? && session_active? && guest_grants.exists?(user_id: user.id)
    end

    def invite_guest!(inviter, user)
      with_lock do
        raise Discourse::InvalidAccess unless allow_guests? && source_type == "category" && can_manage?(inviter)
        raise Discourse::InvalidAccess unless room_id && ::Voice::ParticipantTracker.participant_session?(room_id, inviter.id)
        return false unless self.class.account_eligible?(user)
        guest_grants.find_or_create_by!(user_id: user.id)
      end
      true
    end

    def clear_session_data!
      with_lock do
        guest_grants.delete_all
        ::Voice::Invite.where(room_id: room_id).delete_all if room_id
        Discourse.redis.del(messages_key)
      end
    end

    def messages_key
      "workspace-voice:#{id}:messages"
    end

    def messages_for(user)
      grant = member?(user) ? nil : guest_grants.find_by(user_id: user.id)
      return [] if !member?(user) && !grant
      Discourse.redis.lrange(messages_key, 0, 99).reverse.filter_map do |raw|
        message = JSON.parse(raw)
        message if !grant || message["created_at"] >= grant.created_at.to_f
      end
    end

    def add_message!(user, text)
      raise Discourse::InvalidParameters.new(:text) if text.blank? || text.length > 2000
      message = nil
      with_lock do
        raise Discourse::InvalidAccess unless can_join?(user) && ::Voice::ParticipantTracker.participant_session?(room_id, user.id)
        message = { id: SecureRandom.hex(12), user_id: user.id, username: user.username, text: text, created_at: Time.current.to_f }
        Discourse.redis.multi do |redis|
          redis.lpush(messages_key, message.to_json)
          redis.ltrim(messages_key, 0, 99)
          redis.expire(messages_key, 1.day.to_i)
        end
      end
      ids = ::Voice::ParticipantTracker.user_ids(room_id) & audience_ids
      MessageBus.publish("/workspace-voice/messages/#{id}", { type: "refresh" }, user_ids: ids) if ids.any?
      message
    end

    def native_room
      ::Voice::Room.find_by(id: room_id) if room_id
    end

    def name
      item = source
      source_type == "category" ? item&.name : (item&.name.presence || I18n.t("discourse_workspace_groups.voice.dm_name"))
    end

    def conversation_url
      item = source
      return unless item
      if source_type == "category"
        item.workspace_chat_enabled? && item.category_channel ? item.category_channel.relative_url : item.url
      else
        item.relative_url
      end
    end

    def prepare!(user)
      raise Discourse::InvalidAccess unless can_join?(user)
      save! if new_record?
      with_lock do
        raise Discourse::InvalidAccess unless can_join?(user)
        current = native_room
        if source_type == "dm" &&
             (current.nil? || ::Voice::ParticipantTracker.user_ids(current.id).empty?) &&
             !user.guardian.can_start_voice_call?
          raise Discourse::InvalidAccess
        end
        clear_session_data! if current.nil? || ::Voice::ParticipantTracker.user_ids(current.id).empty?
        unless current
          current = ::Voice::Room.create!(
            creator: Discourse.system_user,
            name: name.to_s.truncate(80),
            slug: "workspace-#{source_type}-#{source_id}",
            public: false,
            ephemeral: true,
            last_occupied_at: Time.current,
          )
          update!(room_id: current.id)
        end
        sync_name!(current)
        current
      end
    end

    def sync_name!(room = native_room)
      return unless room && source
      desired_name = name.to_s.truncate(80)
      room.update!(name: desired_name) if room.name != desired_name
    end

    def reconcile!(end_session: false)
      with_lock { reconcile_session!(end_session: end_session) }
    end

    def reconcile_session!(end_session: false)
      room = native_room
      return unless room
      unless allow_guests?
        ::Voice::Invite.where(room_id: room.id, user_id: guest_grants.select(:user_id)).delete_all
        guest_grants.delete_all
      end
      clear_session_data! if end_session || !available? || !session_active?
      ::Voice::ParticipantTracker.user_ids(room.id).each do |user_id|
        user = User.find_by(id: user_id)
        next if !end_session && can_join?(user)
        ::Voice::Session.where(room_id: room.id, user_id: user_id, left_at: nil).update_all(left_at: Time.current)
        ::Voice::ParticipantTracker.mark_left(room.id, user_id)
        ::Voice::ParticipantTracker.remove(room.id, user_id)
        ::Voice::UserStatusManager.clear_voice_status(user) if user
        ::Voice::Livekit::RoomServiceClient.remove_participant(room, user_id)
        MessageBus.publish("/workspace-voice/revoked/#{user_id}", { room_id: room.id }, user_ids: [user_id])
      end
      if ::Voice::ParticipantTracker.user_ids(room.id).empty?
        ::Voice::Livekit::RoomServiceClient.delete_room(room)
        ::Voice::ParticipantTracker.clear_transport_pin(room.id)
      end
    end

    def self.revoke_group_guest_grants!(user_id, group_id)
      return unless table_exists? && VoiceGuestGrant.table_exists?
      where(source_type: "category").find_each do |binding|
        next unless binding.source&.workspace_group_id == group_id
        binding.guest_grants.where(user_id: user_id).delete_all
      end
    end

    def self.reconcile_active!
      return unless defined?(::Voice::Room) && table_exists?
      where.not(room_id: nil).find_each { |binding| binding.reconcile! }
    end
  end
end
