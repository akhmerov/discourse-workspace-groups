import { module, test } from "qunit";
import {
  shouldRedirectWorkspaceCategory,
  workspaceOverviewRouteParam,
} from "discourse/plugins/discourse-workspace-groups/discourse/api-initializers/workspace-default-overview";

module(
  "Discourse Workspace Groups | Initializer | workspace-default-overview",
  function () {
    test("redirects workspace roots to their overview route", function (assert) {
      const category = { id: 28, slug: "quantum-tinkerer", workspace_kind: "workspace" };

      assert.true(shouldRedirectWorkspaceCategory(category));
      assert.strictEqual(workspaceOverviewRouteParam(category), "quantum-tinkerer/28");
    });

    test("does not redirect ordinary categories", function (assert) {
      assert.false(shouldRedirectWorkspaceCategory({ id: 7, workspace_kind: "channel" }));
      assert.false(shouldRedirectWorkspaceCategory({ id: 7 }));
      assert.false(shouldRedirectWorkspaceCategory(null));
    });
  }
);
