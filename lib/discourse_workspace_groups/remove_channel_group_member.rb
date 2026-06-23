# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class RemoveChannelGroupMember
    attr_reader :group, :user

    def initialize(group:, user:, trigger_user_removed_event: true)
      @group = group
      @user = user
      @trigger_user_removed_event = trigger_user_removed_event
    end

    def call
      group_user = group&.group_users&.find_by(user_id: user&.id)
      return false if group_user.blank?

      group_user.destroy!
      group.trigger_user_removed_event(user) if trigger_user_removed_event?
      Discourse.request_refresh!(user_ids: [user.id])

      true
    end

    private

    def trigger_user_removed_event?
      @trigger_user_removed_event
    end
  end
end
