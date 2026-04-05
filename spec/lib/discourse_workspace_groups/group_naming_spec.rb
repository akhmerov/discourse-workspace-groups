# frozen_string_literal: true

require "securerandom"

RSpec.describe DiscourseWorkspaceGroups do
  fab!(:admin) do
    suffix = SecureRandom.hex(4)
    Fabricate(:admin, username: "wa#{suffix}", email: "workspace-admin-#{suffix}@example.com")
  end
  fab!(:workspace) do
    Fabricate(
      :category,
      name: "Climate Computation Center #{SecureRandom.hex(4)}",
      user: admin,
    )
  end

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

  describe ".disambiguated_channel_group_name" do
    it "keeps channel group slugs unique under normalization collisions" do
      one = described_class.disambiguated_channel_group_name(workspace, "magnetic-graphene-jj")
      two = described_class.disambiguated_channel_group_name(workspace, "magnetic_graphene_jj")

      expect(one).not_to eq(two)
      expect(one).to start_with("chan-")
      expect(two).to start_with("chan-")
      expect(one).to end_with("-#{workspace.id}")
      expect(two).to end_with("-#{workspace.id}")
      expect(one.length).to be <= described_class::MAX_GROUP_NAME_LENGTH
      expect(two.length).to be <= described_class::MAX_GROUP_NAME_LENGTH
    end
  end
end
