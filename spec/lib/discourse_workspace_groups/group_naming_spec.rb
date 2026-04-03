# frozen_string_literal: true

RSpec.describe DiscourseWorkspaceGroups do
  fab!(:workspace) { Fabricate(:category, name: "Climate Computation Center") }

  describe ".workspace_group_name" do
    it "builds a readable workspace group slug" do
      name = described_class.workspace_group_name(workspace)

      expect(name).to start_with("team-")
      expect(name).to end_with("-#{workspace.id}")
      expect(name).to include("climate")
      expect(name.length).to be <= described_class::MAX_GROUP_NAME_LENGTH
    end
  end

  describe ".channel_group_name" do
    it "builds a readable channel group slug" do
      name = described_class.channel_group_name(workspace, "Partner MOU")

      expect(name).to start_with("chan-")
      expect(name).to end_with("-#{workspace.id}")
      expect(name).to include("partner")
      expect(name.length).to be <= described_class::MAX_GROUP_NAME_LENGTH
    end
  end
end
