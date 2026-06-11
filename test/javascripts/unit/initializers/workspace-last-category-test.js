import { module, test } from "qunit";
import {
  normalizeSavedCategoryPath,
  redirectToSavedPath,
  rememberedPathForPage,
} from "discourse/plugins/discourse-workspace-groups/discourse/api-initializers/workspace-last-category";
import { LAST_WORKSPACE_KEY } from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-team-sidebar-state";

const LAST_CATEGORY_KEY = "workspace-groups:last-category-path";
const LEGACY_LAST_CATEGORY_KEY = "research-groups:last-category-path";
const REDIRECT_GUARD_KEY = "workspace-groups:last-category-redirected";
const LEGACY_REDIRECT_GUARD_KEY = "research-groups:last-category-redirected";

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

    test("rejects external and special-scheme saved paths", function (assert) {
      assert.strictEqual(
        normalizeSavedCategoryPath(
          "blob:https://attacker.example/login?phish=1"
        ),
        null
      );
      assert.strictEqual(
        normalizeSavedCategoryPath("//attacker.example/login?phish=1"),
        null
      );
      assert.strictEqual(
        normalizeSavedCategoryPath("https://attacker.example/login?phish=1"),
        null
      );
    });

    test(
      "accepts same-origin saved paths only as root-relative targets",
      function (assert) {
        assert.strictEqual(
          normalizeSavedCategoryPath(
            `${window.location.origin}/c/quantum-tinkerer/28?order=latest`
          ),
          "/c/quantum-tinkerer/28?order=latest"
        );
      }
    );

    test("rejects external remembered paths", function (assert) {
      assert.strictEqual(
        rememberedPathForPage("blob:https://attacker.example/login?phish=1"),
        null
      );
    });

    test("redirects to the saved category through the Ember router", function (assert) {
      const replaceCalls = [];
      const router = {
        replaceWith(path) {
          replaceCalls.push(path);
        },
      };

      localStorage.setItem(LAST_CATEGORY_KEY, "/c/quantum-tinkerer/28");
      localStorage.removeItem(LEGACY_LAST_CATEGORY_KEY);
      localStorage.removeItem(LAST_WORKSPACE_KEY);
      sessionStorage.removeItem(REDIRECT_GUARD_KEY);
      sessionStorage.removeItem(LEGACY_REDIRECT_GUARD_KEY);

      try {
        assert.true(
          redirectToSavedPath(router, { pathname: "/", search: "", hash: "" })
        );
      } finally {
        localStorage.removeItem(LAST_CATEGORY_KEY);
        sessionStorage.removeItem(REDIRECT_GUARD_KEY);
      }

      assert.deepEqual(replaceCalls, ["/c/quantum-tinkerer/28"]);
    });
  }
);
