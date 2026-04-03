import { module, test } from "qunit";
import {
  currentScopedMode,
  pairedCategoryChannelFor,
  sidebarChannelCategories,
  sidebarScopedCategories,
  userSelectedScopedCategories,
  workspaceScopedCategory,
} from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-team-sidebar-state";

module(
  "Discourse Workspace Groups | Lib | workspace-team-sidebar-state",
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

    test("uses the selected channel subset when the user narrowed sidebar categories", function (assert) {
      const workspace = {
        id: 40,
        parent_category_id: null,
        workspace_kind: "workspace",
      };
      const channelA = {
        id: 41,
        parent_category_id: 40,
        workspace_kind: "channel",
      };
      const channelB = {
        id: 42,
        parent_category_id: 40,
        workspace_kind: "channel",
      };

      assert.deepEqual(
        userSelectedScopedCategories(
          { sidebarCategoryIds: [42] },
          [workspace, channelA, channelB]
        ),
        [workspace, channelB]
      );
    });

    test("limits visible team channels to categories with followed paired chat channels", function (assert) {
      const workspace = {
        id: 40,
        parent_category_id: null,
        workspace_kind: "workspace",
      };
      const joinedChannel = {
        id: 41,
        parent_category_id: 40,
        workspace_kind: "channel",
      };
      const unjoinedChannel = {
        id: 42,
        parent_category_id: 40,
        workspace_kind: "channel",
      };

      const visibleChannels = sidebarChannelCategories({
        currentUser: {},
        router: {
          currentRoute: {
            attributes: {
              category: workspace,
            },
          },
        },
        site: {
          categoriesList: [workspace, joinedChannel, unjoinedChannel],
        },
        siteSettings: {},
        chatChannelsManager: {
          channels: [
            {
              isCategoryChannel: true,
              chatableId: 41,
              currentUserMembership: { following: true },
            },
            {
              isCategoryChannel: true,
              chatableId: 42,
              currentUserMembership: { following: false },
            },
          ],
        },
      });

      assert.deepEqual(visibleChannels, [joinedChannel]);
    });

    test("detects chat mode for category-backed chat channels", function (assert) {
      assert.strictEqual(
        currentScopedMode({
          router: { currentRouteName: "chat.channel" },
          chat: {
            activeChannel: {
              isCategoryChannel: true,
            },
          },
        }),
        "chat"
      );
    });

    test("finds the followed paired category channel", function (assert) {
      const category = { id: 41 };

      assert.deepEqual(
        pairedCategoryChannelFor(category, {
          channels: [
            {
              id: 9,
              isCategoryChannel: true,
              chatableId: 41,
              currentUserMembership: { following: true },
            },
          ],
        }),
        {
          id: 9,
          isCategoryChannel: true,
          chatableId: 41,
          currentUserMembership: { following: true },
        }
      );
    });
  }
);
