import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import WorkspaceChannelActions from "discourse/plugins/discourse-workspace-groups/discourse/connectors/before-create-topic-button/workspace-channel-actions";

module(
  "Discourse Workspace Groups | Connector | workspace-channel-actions",
  function (hooks) {
    setupRenderingTest(hooks);

    test("uses the outlet category when no cached category is available", async function (assert) {
      this.outletArgs = { category: { id: 42, workspace_can_enable: true } };

      await render(
        <template>
          <WorkspaceChannelActions @outletArgs={{this.outletArgs}} />
        </template>
      );

      assert.dom(".workspace-groups-actions__button").exists();
    });
  }
);
