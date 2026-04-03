import { module, test } from "qunit";
import {
  sidebarScopedCategories,
  workspaceScopedCategory,
} from "discourse/plugins/discourse-workspace-groups/discourse/api-initializers/workspace-team-sidebar";

module(
  "Discourse Workspace Groups | Initializer | workspace-team-sidebar",
  function () {
    test("only treats workspace categories as scoped sidebar categories", function (assert) {
      const regularCategory = {
        id: 28,
        parent_category_id: null,
      };

      assert.strictEqual(workspaceScopedCategory(regularCategory), null);
    });

    test("does not scope regular category trees", function (assert) {
      const regularCategory = {
        id: 28,
        parent_category_id: null,
      };
      const regularChild = {
        id: 29,
        parent_category_id: 28,
      };

      const scopedCategories = sidebarScopedCategories({
        router: {
          currentRoute: {
            attributes: {
              category: regularCategory,
            },
          },
        },
        site: {
          categoriesList: [regularCategory, regularChild],
        },
        siteSettings: {
          allow_uncategorized_topics: false,
        },
      });

      assert.strictEqual(scopedCategories, null);
    });

    test("scopes real workspace categories", function (assert) {
      const workspace = {
        id: 40,
        parent_category_id: null,
        workspace_kind: "workspace",
      };
      const channel = {
        id: 41,
        parent_category_id: 40,
        workspace_kind: "channel",
      };

      const scopedCategories = sidebarScopedCategories({
        router: {
          currentRoute: {
            attributes: {
              category: workspace,
            },
          },
        },
        site: {
          categoriesList: [workspace, channel],
        },
        siteSettings: {
          allow_uncategorized_topics: false,
        },
      });

      assert.deepEqual(scopedCategories, [workspace, channel]);
    });
  }
);
