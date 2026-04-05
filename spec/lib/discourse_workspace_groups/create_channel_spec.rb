# frozen_string_literal: true

require "securerandom"

RSpec.describe DiscourseWorkspaceGroups::CreateChannel do
  fab!(:admin) do
    suffix = SecureRandom.hex(4)
    Fabricate(:admin, username: "wa#{suffix}", email: "workspace-admin-#{suffix}@example.com")
  end
  fab!(:other_user) do
    suffix = SecureRandom.hex(4)
    Fabricate(:user, username: "wu#{suffix}", email: "workspace-user-#{suffix}@example.com")
  end
  fab!(:category) { Fabricate(:category, name: "Workspace #{SecureRandom.hex(4)}", user: admin) }

  let!(:workspace) do
    DiscourseWorkspaceGroups::EnsureWorkspace.new(category: category, user: admin).call
  end

  before do
    SiteSetting.discourse_workspace_groups_enabled = true
    SiteSetting.chat_enabled = false
  end

  it "creates private channels with only the creator as a member" do
    channel_name = "Secret Lab #{SecureRandom.hex(4)}"

    expect(workspace.workspace_group.name).to eq(
      DiscourseWorkspaceGroups.workspace_group_name(workspace),
    )

    expect {
        described_class.new(
          workspace: workspace,
          user: admin,
          name: channel_name,
          description: nil,
          visibility: "private",
        ).call
    }.to change(Category, :count).by(1)

    channel = Category.last

    expect(channel.workspace_visibility).to eq("private")
    expect(channel.workspace_group.name).to eq(
      DiscourseWorkspaceGroups.channel_group_name(workspace, channel_name),
    )
    expect(channel.workspace_group.users).to contain_exactly(admin)
    expect(workspace.workspace_group.users).not_to include(other_user)
    expect(
      workspace.reload.category_groups.find_by(group_id: channel.workspace_group.id).permission_type,
    ).to eq(CategoryGroup.permission_types[:readonly])
  end

  it "creates globally unique paired chat slugs for duplicate channel names across workspaces" do
    SiteSetting.chat_enabled = true
    SiteSetting.enable_public_channels = true

    other_category =
      Fabricate(:category, name: "Workspace #{SecureRandom.hex(4)}", user: admin)
    other_workspace =
      DiscourseWorkspaceGroups::EnsureWorkspace.new(category: other_category, user: admin).call
    channel_name = "Reading Group"

    channel_one =
      described_class.new(
        workspace: workspace,
        user: admin,
        name: channel_name,
        description: nil,
        visibility: "public",
      ).call
    channel_two =
      described_class.new(
        workspace: other_workspace,
        user: admin,
        name: channel_name,
        description: nil,
        visibility: "public",
      ).call

    expect(channel_one.reload.category_channel.slug).to start_with("#{workspace.slug}-reading-group")
    expect(channel_two.reload.category_channel.slug).to start_with(
      "#{other_workspace.slug}-reading-group",
    )
    expect(channel_one.slug).to start_with("reading-group")
    expect(channel_two.slug).to start_with("#{other_workspace.slug}-reading-group")
    expect(channel_one.category_channel.slug).to end_with("-#{channel_one.id}")
    expect(channel_two.category_channel.slug).to end_with("-#{channel_two.id}")
    expect(channel_one.slug).not_to eq(channel_two.slug)
    expect(channel_one.category_channel.slug).not_to eq(channel_two.category_channel.slug)
  end

  it "keeps the full description in the category topic while capping the paired chat description" do
    SiteSetting.chat_enabled = true
    SiteSetting.enable_public_channels = true

    long_description = ("Research summary paragraph. " * 30).strip

    channel =
      described_class.new(
        workspace: workspace,
        user: admin,
        name: "Long Description #{SecureRandom.hex(3)}",
        description: long_description,
        visibility: "public",
      ).call

    expect(channel.topic.first_post.raw).to eq(long_description)
    expect(channel.reload.category_channel.description.length).to be <= 500
    expect(channel.category_channel.description).to start_with("Research summary paragraph.")
  end

  it "creates distinct backing groups for names that normalize to the same slug" do
    channel_one =
      described_class.new(
        workspace: workspace,
        user: admin,
        name: "magnetic-graphene-jj",
        description: nil,
        visibility: "private",
      ).call
    channel_two =
      described_class.new(
        workspace: workspace,
        user: admin,
        name: "magnetic_graphene_jj",
        description: nil,
        visibility: "private",
      ).call

    expect(channel_one.workspace_group_id).not_to eq(channel_two.workspace_group_id)
    expect(channel_one.workspace_group.name).not_to eq(channel_two.workspace_group.name)
    expect(channel_one.slug).not_to eq(channel_two.slug)
    expect(channel_one.workspace_group.name.length).to be <= DiscourseWorkspaceGroups::MAX_GROUP_NAME_LENGTH
    expect(channel_two.workspace_group.name.length).to be <= DiscourseWorkspaceGroups::MAX_GROUP_NAME_LENGTH
  end

  it "keeps public root permissions when adding channels to a public workspace" do
    workspace.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_ROOT_PUBLIC_READ] = true
    workspace.save!
    DiscourseWorkspaceGroups.sync_workspace_root_permissions!(workspace)

    described_class.new(
      workspace: workspace,
      user: admin,
      name: "Open Research #{SecureRandom.hex(3)}",
      description: nil,
      visibility: "public",
    ).call

    everyone_permission = workspace.reload.category_groups.find_by(group_id: Group::AUTO_GROUPS[:everyone])
    expect(everyone_permission&.permission_type).to eq(CategoryGroup.permission_types[:readonly])
  end
end
