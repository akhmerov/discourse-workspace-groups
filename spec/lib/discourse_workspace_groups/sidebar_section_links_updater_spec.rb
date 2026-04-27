# frozen_string_literal: true

RSpec.describe SidebarSectionLinksUpdater do
  fab!(:user)
  fab!(:category_1, :category)
  fab!(:category_2, :category)
  fab!(:category_3, :category)

  it "does not cap category sidebar links when workspace groups are enabled" do
    SiteSetting.discourse_workspace_groups_enabled = true

    stub_const(SidebarSection, :MAX_USER_CATEGORY_LINKS, 2) do
      described_class.update_category_section_links(
        user,
        category_ids: [category_1.id, category_2.id, category_3.id],
      )
    end

    expect(SidebarSectionLink.where(linkable_type: "Category", user: user).count).to eq(3)
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
