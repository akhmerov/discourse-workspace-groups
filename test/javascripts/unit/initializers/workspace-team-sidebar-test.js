import { module, test } from "qunit";
import {
  currentScopedMode,
  memberWorkspaceCategories,
  pairedCategoryChannelFor,
  rememberedOrDefaultWorkspaceCategory,
  rememberedWorkspaceCategory,
  sidebarChannelCategories,
  sidebarScopedCategories,
  userSelectedScopedCategories,
  workspaceScopedCategory,
} from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-team-sidebar-state";

module(
  "Discourse Workspace Groups | Lib | workspace-team-sidebar-state",
  function (hooks) {
    hooks.beforeEach(function () {
      localStorage.removeItem("workspace-groups:last-workspace-id");
    });

    hooks.afterEach(function () {
      localStorage.removeItem("workspace-groups:last-workspace-id");
    });

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

    test("sorts muted team channels after unmuted ones", function (assert) {
      const workspace = {
        id: 40,
        parent_category_id: null,
        workspace_kind: "workspace",
      };
      const mutedChannel = {
        id: 41,
        parent_category_id: 40,
        workspace_kind: "channel",
      };
      const unmutedChannel = {
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
          categoriesList: [workspace, mutedChannel, unmutedChannel],
        },
        siteSettings: {},
        chatChannelsManager: {
          channels: [
            {
              isCategoryChannel: true,
              chatableId: 41,
              currentUserMembership: { following: true, muted: true },
            },
            {
              isCategoryChannel: true,
              chatableId: 42,
              currentUserMembership: { following: true, muted: false },
            },
          ],
        },
      });

      assert.deepEqual(visibleChannels, [unmutedChannel, mutedChannel]);
    });

    test("keeps the current channel visible while local sidebar state catches up", function (assert) {
      const workspace = {
        id: 40,
        parent_category_id: null,
        workspace_kind: "workspace",
      };
      const existingChannel = {
        id: 41,
        parent_category_id: 40,
        workspace_kind: "channel",
      };
      const currentChannel = {
        id: 42,
        parent_category_id: 40,
        workspace_kind: "channel",
      };

      const visibleChannels = sidebarChannelCategories({
        currentUser: { sidebarCategoryIds: [41] },
        router: {
          currentRoute: {
            attributes: {
              category: currentChannel,
            },
          },
        },
        site: {
          categoriesList: [workspace, existingChannel, currentChannel],
        },
        siteSettings: {},
        chatChannelsManager: {
          channels: [
            {
              isCategoryChannel: true,
              chatableId: 41,
              currentUserMembership: { following: true },
            },
          ],
        },
      });

      assert.deepEqual(visibleChannels, [existingChannel, currentChannel]);
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

    test("uses the remembered workspace when there is no active scoped category", function (assert) {
      const workspace = {
        id: 40,
        parent_category_id: null,
        workspace_kind: "workspace",
        workspace_group_id: 400,
      };
      const channel = {
        id: 41,
        parent_category_id: 40,
        workspace_kind: "channel",
      };

      localStorage.setItem("workspace-groups:last-workspace-id", "40");

      assert.strictEqual(
        rememberedWorkspaceCategory({
          currentUser: {},
          site: { categoriesList: [workspace, channel] },
          siteSettings: {},
        }),
        workspace
      );

      assert.deepEqual(
        sidebarScopedCategories({
          currentUser: {},
          router: { currentRoute: { attributes: {} } },
          site: { categoriesList: [workspace, channel] },
          siteSettings: {},
        }),
        [workspace, channel]
      );
    });

    test("defaults to the first member workspace when none was remembered", function (assert) {
      const guestWorkspace = {
        id: 10,
        parent_category_id: null,
        workspace_kind: "workspace",
        workspace_group_id: 110,
      };
      const memberWorkspace = {
        id: 20,
        parent_category_id: null,
        workspace_kind: "workspace",
        workspace_group_id: 220,
      };
      const memberChannel = {
        id: 21,
        parent_category_id: 20,
        workspace_kind: "channel",
      };

      const services = {
        currentUser: { groups: [{ id: 220 }] },
        router: { currentRoute: { attributes: {} } },
        site: { categoriesList: [guestWorkspace, memberWorkspace, memberChannel] },
        siteSettings: {},
      };

      assert.deepEqual(memberWorkspaceCategories(services), [memberWorkspace]);
      assert.strictEqual(
        rememberedOrDefaultWorkspaceCategory(services),
        memberWorkspace
      );
      assert.deepEqual(sidebarScopedCategories(services), [memberWorkspace, memberChannel]);
    });

    test("does not auto-pick a workspace for users without workspace memberships", function (assert) {
      const guestWorkspace = {
        id: 10,
        parent_category_id: null,
        workspace_kind: "workspace",
        workspace_group_id: 110,
      };

      const services = {
        currentUser: { groups: [] },
        router: { currentRoute: { attributes: {} } },
        site: { categoriesList: [guestWorkspace] },
        siteSettings: {},
      };

      assert.deepEqual(memberWorkspaceCategories(services), []);
      assert.strictEqual(rememberedOrDefaultWorkspaceCategory(services), null);
      assert.strictEqual(sidebarScopedCategories(services), null);
    });
  }
);
