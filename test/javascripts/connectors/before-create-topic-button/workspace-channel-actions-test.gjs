import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import WorkspaceChannelActions from "discourse/plugins/discourse-workspace-groups/discourse/connectors/before-create-topic-button/workspace-channel-actions";

module(
  "Discourse Workspace Groups | Connector | workspace-channel-actions",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      this.site = this.owner.lookup("service:site");
      this.originalCategoriesById = this.site.categoriesById;
    });

    hooks.afterEach(function () {
      this.site.categoriesById = this.originalCategoriesById;
    });

    test("resolves categories from plain object category lookup", async function (assert) {
      this.site.categoriesById = {
        42: { id: 42, workspace_can_enable: true },
      };
      this.outletArgs = { category: { id: 42 } };

      await render(
        <template>
          <WorkspaceChannelActions @outletArgs={{this.outletArgs}} />
        </template>
      );

      assert.dom(".workspace-groups-actions__button").exists();
    });
  }
);
