# frozen_string_literal: true

RSpec.describe SidebarSectionLinksUpdater do
  fab!(:user)
  fab!(:category_1, :category)
  fab!(:category_2, :category)
  fab!(:category_3, :category)

  def mark_as_workspace_channel(category)
    category.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_ENABLED] = true
    category.custom_fields[DiscourseWorkspaceGroups::WORKSPACE_KIND] =
      DiscourseWorkspaceGroups::WORKSPACE_KIND_CHANNEL
    category.save_custom_fields(true)
  end

  it "preserves the core cap for non-workspace category sidebar links when workspace groups are enabled" do
    SiteSetting.discourse_workspace_groups_enabled = true

    stub_const(SidebarSection, :MAX_USER_CATEGORY_LINKS, 2) do
      described_class.update_category_section_links(
        user,
        category_ids: [category_1.id, category_2.id, category_3.id],
      )
    end

    expect(SidebarSectionLink.where(linkable_type: "Category", user: user).count).to eq(2)
  end

  it "allows workspace channel sidebar links beyond the core category cap" do
    SiteSetting.discourse_workspace_groups_enabled = true
    [category_1, category_2, category_3].each do |category|
      mark_as_workspace_channel(category)
    end

    stub_const(SidebarSection, :MAX_USER_CATEGORY_LINKS, 2) do
      described_class.update_category_section_links(
        user,
        category_ids: [category_1.id, category_2.id, category_3.id],
      )
    end

    expect(SidebarSectionLink.where(linkable_type: "Category", user: user).count).to eq(3)
  end

  it "caps workspace channel sidebar links before querying categories" do
    SiteSetting.discourse_workspace_groups_enabled = true
    [category_1, category_2, category_3].each do |category|
      mark_as_workspace_channel(category)
    end

    stub_const(
      DiscourseWorkspaceGroups::WorkspaceSidebarCategoryLinks,
      :MAX_WORKSPACE_CATEGORY_LINKS,
      2,
    ) do
      stub_const(SidebarSection, :MAX_USER_CATEGORY_LINKS, 1) do
        described_class.update_category_section_links(
          user,
          category_ids: [category_1.id, category_2.id, category_3.id],
        )
      end
    end

    expect(SidebarSectionLink.where(linkable_type: "Category", user: user).count).to eq(2)
  end

  it "preserves the core cap when workspace groups are disabled" do
    SiteSetting.discourse_workspace_groups_enabled = false

    stub_const(SidebarSection, :MAX_USER_CATEGORY_LINKS, 2) do
      described_class.update_category_section_links(
        user,
        category_ids: [category_1.id, category_2.id, category_3.id],
      )
    end

    expect(SidebarSectionLink.where(linkable_type: "Category", user: user).count).to eq(2)
  end
end
