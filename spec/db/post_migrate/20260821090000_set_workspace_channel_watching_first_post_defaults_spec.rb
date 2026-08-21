# frozen_string_literal: true

require Rails.root.join(
          "plugins/discourse-workspace-groups/db/post_migrate/20260821090000_set_workspace_channel_watching_first_post_defaults.rb",
        )

RSpec.describe SetWorkspaceChannelWatchingFirstPostDefaults do
  fab!(:admin)
  fab!(:muted_user, :user)
  fab!(:defaulted_user, :user)
  fab!(:category) { Fabricate(:category, user: admin) }

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = false
    @original_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
  end

  after { ActiveRecord::Migration.verbose = @original_verbose }

  it "sets native defaults and backfills only members without an explicit preference" do
    workspace =
      DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call
    channel =
      DiscourseWorkspaceGroups::CreateChannel.new(
        workspace: workspace,
        user: admin,
        name: "Existing Channel",
        description: nil,
        visibility: DiscourseWorkspaceGroups::VISIBILITY_PRIVATE,
      ).call

    channel.workspace_group.add(muted_user)
    channel.workspace_group.add(defaulted_user)
    GroupCategoryNotificationDefault.where(
      group: channel.workspace_group,
      category: channel,
    ).delete_all
    CategoryUser.where(category: channel).delete_all
    CategoryUser.create!(
      category: channel,
      user: muted_user,
      notification_level: NotificationLevels.all[:muted],
    )

    2.times { described_class.new.up }

    expect(
      GroupCategoryNotificationDefault.find_by!(
        group: channel.workspace_group,
        category: channel,
      ).notification_level,
    ).to eq(NotificationLevels.all[:watching_first_post])
    expect(CategoryUser.find_by!(user: admin, category: channel).notification_level).to eq(
      NotificationLevels.all[:watching_first_post],
    )
    expect(CategoryUser.find_by!(user: defaulted_user, category: channel).notification_level).to eq(
      NotificationLevels.all[:watching_first_post],
    )
    expect(CategoryUser.find_by!(user: muted_user, category: channel).notification_level).to eq(
      NotificationLevels.all[:muted],
    )
  end
end
