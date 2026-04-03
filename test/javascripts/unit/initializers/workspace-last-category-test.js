import { module, test } from "qunit";
import {
  normalizeSavedCategoryPath,
  rememberedPathForPage,
} from "discourse/plugins/discourse-workspace-groups/discourse/api-initializers/workspace-last-category";

module(
  "Discourse Workspace Groups | Initializer | workspace-last-category",
  function () {
    test("normalizes legacy overview paths back to category paths", function (assert) {
      assert.strictEqual(
        normalizeSavedCategoryPath("/c/quantum-tinkerer/28/overview"),
        "/c/quantum-tinkerer/28"
      );
    });

    test("remembers the category path instead of the current overview URL", function (assert) {
      assert.strictEqual(
        rememberedPathForPage("/c/quantum-tinkerer/28/overview", {
          path: "/c/quantum-tinkerer/28",
        }),
        "/c/quantum-tinkerer/28"
      );
    });
  }
);
