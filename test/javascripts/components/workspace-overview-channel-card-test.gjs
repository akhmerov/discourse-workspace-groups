import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import WorkspaceOverviewChannelCard from "discourse/plugins/discourse-workspace-groups/discourse/components/workspace-overview-channel-card";

module(
  "Discourse Workspace Groups | Component | workspace-overview-channel-card",
  function (hooks) {
    setupRenderingTest(hooks);

    test("renders membership, access, and archive actions in the same action row", async function (assert) {
      this.channel = {
        name: "Lab Notes",
        description: "Bench logs and prototype notes.",
        visibility: "public",
        member_count: 4,
        members_url: "/g/lab-notes",
        topics_url: "/c/quantum-tinkerer/lab-notes/29",
        can_open_topics: true,
        can_view_members: true,
        can_join: false,
        can_leave: true,
        can_manage_access: true,
        can_archive: true,
        can_unarchive: false,
        archived: false,
        is_pending: false,
      };

      this.noop = () => {};

      await render(
        <template>
          <WorkspaceOverviewChannelCard
            @channel={{this.channel}}
            @onJoin={{this.noop}}
            @onLeave={{this.noop}}
            @onManageAccess={{this.noop}}
            @onArchive={{this.noop}}
            @onUnarchive={{this.noop}}
          />
        </template>
      );

      assert.dom(".workspace-groups-overview__card-actions").exists();
      assert.dom(".workspace-groups-overview__card-actions .btn").exists({
        count: 3,
      });
      assert
        .dom(".workspace-groups-overview__card-actions")
        .hasText("Leave Access Archive");
    });
  }
);
