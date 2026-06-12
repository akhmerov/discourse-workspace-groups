# frozen_string_literal: true

require "json"

RSpec.describe "workspace sidebar layout normalization" do
  let(:contracts) do
    path =
      File.expand_path(
        "../../../assets/javascripts/discourse/lib/workspace-sidebar-layout-contracts.js",
        __dir__,
      )

    contract_source = File.read(path)
    contract_json = contract_source.match(/\Aexport const contracts = (?<json>\[.*\]);/m)[:json]

    JSON.parse(contract_json)
  end

  it "matches the shared normalization contracts" do
    contracts.each do |contract|
      normalized =
        DiscourseWorkspaceGroups
          .normalize_workspace_sidebar_layout(contract.fetch("input"))
          .deep_stringify_keys

      expect(normalized).to eq(contract.fetch("normalized")), contract.fetch("name")
    end
  end
end
