# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class RemoveChannelGroupMember
    attr_reader :group, :user

    def initialize(group:, user:)
      @group = group
      @user = user
    end

    def call
      group_user = group&.group_users&.find_by(user_id: user&.id)
      return false if group_user.blank?

      group_user.destroy!
      group.trigger_user_removed_event(user)
      Discourse.request_refresh!(user_ids: [user.id])

      true
    end
  end
end
