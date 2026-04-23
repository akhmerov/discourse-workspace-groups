# frozen_string_literal: true

require "digest/sha1"

module ::DiscourseWorkspaceGroups
  class UpdateChannel
    CATEGORY_SLUG_HASH_LENGTH = 4
    UNSET = Object.new.freeze

    attr_reader :channel,
                :user,
                :name,
                :description,
                :visibility,
                :channel_mode,
                :allow_channel_wide_mentions,
                :color,
                :style_type,
                :emoji,
                :icon

    def initialize(
      channel:,
      user:,
      name:,
      description:,
      visibility:,
      channel_mode: nil,
      allow_channel_wide_mentions: nil,
      color: UNSET,
      style_type: UNSET,
      emoji: UNSET,
      icon: UNSET
    )
      @channel = channel
      @user = user
      @name = name.to_s.strip
      @description = description.to_s.strip
      @visibility = visibility.presence || channel.workspace_visibility
      @channel_mode = channel_mode.presence || channel.workspace_channel_mode
      @allow_channel_wide_mentions =
        if allow_channel_wide_mentions.nil?
          current_allow_channel_wide_mentions
        else
          ActiveModel::Type::Boolean.new.cast(allow_channel_wide_mentions)
        end
      @color = color == UNSET ? channel.color : normalize_color(color)
      @style_type = style_type == UNSET ? channel.style_type : style_type.to_s.presence
      @emoji = emoji == UNSET ? channel.emoji : emoji.to_s.presence
      @icon = icon == UNSET ? channel.icon : icon.to_s.presence
      @emoji = nil if @style_type != "emoji"
      @icon = nil if @style_type != "icon"
    end

    def call
      validate!

      Category.transaction do
        rename_channel_group! if name_changed?
        update_category!
        update_description!
        update_visibility!
        update_channel_mode!
        sync_chat_channel!
      end

      channel.reload
    end

    private

    def validate!
      raise Discourse::InvalidAccess if user.blank?
      raise Discourse::InvalidAccess if !channel&.workspace_channel?
      raise Discourse::InvalidAccess if !DiscourseWorkspaceGroups.can_manage_workspace_channel?(channel, user)
      raise Discourse::InvalidParameters.new(:name) if name.blank?
      raise Discourse::InvalidParameters.new(:visibility) if !valid_visibility?
      raise Discourse::InvalidParameters.new(:channel_mode) if !valid_channel_mode?
      raise Discourse::InvalidParameters.new(:color) if !valid_color?
      raise Discourse::InvalidParameters.new(:style_type) if !valid_style_type?
      raise Discourse::InvalidParameters.new(:emoji) if style_type == "emoji" && emoji.blank?
      if visibility == VISIBILITY_PRIVATE && channel.workspace_visibility != VISIBILITY_PRIVATE &&
           !DiscourseWorkspaceGroups.can_create_private_workspace_channel?(workspace, user)
        raise Discourse::InvalidAccess
      end
    end

    def valid_visibility?
      [VISIBILITY_PUBLIC, VISIBILITY_PRIVATE].include?(visibility)
    end

    def valid_channel_mode?
      DiscourseWorkspaceGroups.valid_channel_mode?(channel_mode)
    end

    def valid_color?
      color.present? && color.match?(/\A\h{6}\z/)
    end

    def valid_style_type?
      %w[square emoji icon].include?(style_type)
    end

    def workspace
      channel.workspace_parent_category
    end

    def name_changed?
      channel.name != name
    end

    def description_changed?
      current_description != description
    end

    def visibility_changed?
      channel.workspace_visibility != visibility
    end

    def channel_mode_changed?
      channel.workspace_channel_mode != channel_mode
    end

    def style_changed?
      channel.color != color || channel.style_type != style_type || channel.emoji != emoji ||
        channel.icon != icon
    end

    def allow_channel_wide_mentions_changed?
      current_allow_channel_wide_mentions != allow_channel_wide_mentions
    end

    def current_description
      channel.topic&.first_post&.raw.to_s.strip
    end

    def current_allow_channel_wide_mentions
      channel.category_channel&.allow_channel_wide_mentions != false
    end

    def rename_channel_group!
      group = channel.workspace_group
      return if group.blank?

      group.update!(name: desired_group_name, full_name: name)
    end

    def update_category!
      attrs = {}

      if name_changed?
        attrs[:name] = name
        attrs[:slug] = desired_category_slug
      end

      if style_changed?
        attrs[:color] = color
        attrs[:style_type] = style_type
        attrs[:emoji] = emoji
        attrs[:icon] = icon
      end

      channel.update!(attrs) if attrs.present?
    end

    def update_description!
      return if !description_changed?

      first_post = channel.topic&.first_post
      return if first_post.blank?

      first_post.revise(user, { raw: description }, skip_validations: true)
      first_post.reload
      channel.update_column(:description, first_post.cooked.presence)
    end

    def update_visibility!
      return if !visibility_changed?

      channel.custom_fields[WORKSPACE_VISIBILITY] = visibility
      channel.save_custom_fields(true)
    end

    def update_channel_mode!
      return if !channel_mode_changed?

      channel.custom_fields[WORKSPACE_CHANNEL_MODE] = channel_mode
      channel.set_permissions(DiscourseWorkspaceGroups.channel_permissions(channel.workspace_group, channel_mode))
      channel.save!
    end

    def sync_chat_channel!
      chat_channel = DiscourseWorkspaceGroups::SyncCategoryChatChannel.new(category: channel, user: user).call
      return if chat_channel.blank?
      return if !allow_channel_wide_mentions_changed?

      chat_channel.update!(allow_channel_wide_mentions: allow_channel_wide_mentions)
      Chat::Publisher.publish_chat_channel_edit(chat_channel, user)
    end

    def desired_group_name
      group_name = DiscourseWorkspaceGroups.channel_group_name(workspace, name)
      existing_group = Group.find_by(name: group_name)
      return group_name if existing_group.blank? || existing_group.id == channel.workspace_group_id

      raise Discourse::InvalidParameters.new(collision_error) if existing_group.full_name == name

      group_name = DiscourseWorkspaceGroups.disambiguated_channel_group_name(workspace, name)
      existing_group = Group.find_by(name: group_name)
      return group_name if existing_group.blank? || existing_group.id == channel.workspace_group_id

      raise Discourse::InvalidParameters.new(collision_error)
    end

    def desired_category_slug
      base_slug = Slug.for(name, "").presence || "channel"
      return base_slug if !Category.where(slug: base_slug).where.not(id: channel.id).exists?

      workspace_scoped_slug = Slug.for("#{workspace.slug}-#{name}", "").presence
      if workspace_scoped_slug.present? &&
           !Category.where(slug: workspace_scoped_slug).where.not(id: channel.id).exists?
        return workspace_scoped_slug
      end

      suffix = "-#{Digest::SHA1.hexdigest("#{workspace.id}:#{name}")[0, CATEGORY_SLUG_HASH_LENGTH]}"
      scoped_base = workspace_scoped_slug.presence || base_slug
      candidate = "#{scoped_base.first(255 - suffix.length)}#{suffix}"
      return candidate if !Category.where(slug: candidate).where.not(id: channel.id).exists?

      raise Discourse::InvalidParameters.new(collision_error)
    end

    def normalize_color(value)
      value.to_s.strip.delete_prefix("#").upcase
    end

    def collision_error
      I18n.t("discourse_workspace_groups.errors.channel_name_collision", name: name)
    end
  end
end
