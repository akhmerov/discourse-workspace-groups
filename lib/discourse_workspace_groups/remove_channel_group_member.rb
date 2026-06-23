# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class RemoveChannelGroupMember
    attr_reader :group, :user

    def initialize(group:, user:)
      @group = group
      @user = user
    end

    def call
      return false if group.blank? || user.blank?

      group.remove(user)
    end
  end
end
