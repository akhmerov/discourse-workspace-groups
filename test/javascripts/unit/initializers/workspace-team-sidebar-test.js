import { module, test } from "qunit";
import {
  chatChannelHasUnread,
  currentScopedMode,
  focusedWorkspaceCategory,
  memberWorkspaceCategories,
  pairedCategoryChannelFor,
  readWorkspaceUnreadFilter,
  rememberedOrDefaultWorkspaceCategory,
  rememberedWorkspaceCategory,
  sidebarChannelCategories,
  sidebarScopedCategories,
  userSelectedScopedCategories,
  WORKSPACE_FOCUS_KEY,
  WORKSPACE_UNREAD_FILTER_KEY,
  workspaceScopedCategory,
  workspaceSidebarChannelOrder,
  workspaceSidebarSectionChannelOrder,
  writeWorkspaceUnreadFilter,
} from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-team-sidebar-state";

module(
  "Discourse Workspace Groups | Lib | workspace-team-sidebar-state",
  function (hooks) {
    hooks.beforeEach(function () {
      localStorage.removeItem("workspace-groups:last-workspace-id");
      localStorage.removeItem(WORKSPACE_UNREAD_FILTER_KEY);
      sessionStorage.removeItem(WORKSPACE_FOCUS_KEY);
    });

    hooks.afterEach(function () {
      localStorage.removeItem("workspace-groups:last-workspace-id");
      localStorage.removeItem(WORKSPACE_UNREAD_FILTER_KEY);
      sessionStorage.removeItem(WORKSPACE_FOCUS_KEY);
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

    test("hides archived team channels even when their chat channel is loaded", function (assert) {
      const workspace = {
        id: 40,
        parent_category_id: null,
        workspace_kind: "workspace",
      };
      const activeChannel = {
        id: 41,
        parent_category_id: 40,
        workspace_kind: "channel",
      };
      const archivedChannel = {
        id: 42,
        parent_category_id: 40,
        workspace_kind: "channel",
        workspace_archived: true,
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
          categoriesList: [workspace, activeChannel, archivedChannel],
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
              currentUserMembership: { following: true },
            },
          ],
        },
      });

      assert.deepEqual(visibleChannels, [activeChannel]);
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

    test("uses a saved per-user workspace sidebar order when present", function (assert) {
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
        currentUser: {
          workspaceSidebarOrders: { "40": [41, 42] },
        },
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

      assert.deepEqual(visibleChannels, [mutedChannel, unmutedChannel]);
      assert.deepEqual(
        workspaceSidebarChannelOrder(
          { workspaceSidebarOrders: { "40": [41, 42] } },
          40
        ),
        [41, 42]
      );
    });

    test("uses saved per-user workspace sidebar sections before legacy order", function (assert) {
      const workspace = {
        id: 40,
        parent_category_id: null,
        workspace_kind: "workspace",
      };
      const firstChannel = {
        id: 41,
        parent_category_id: 40,
        workspace_kind: "channel",
      };
      const secondChannel = {
        id: 42,
        parent_category_id: 40,
        workspace_kind: "channel",
      };

      const currentUser = {
        workspaceSidebarOrders: { "40": [41, 42] },
        workspaceSidebarSections: {
          "40": {
            sections: [
              { id: "papers", title: "Papers", channel_ids: [42] },
              { id: "other", title: "Other", channel_ids: [41] },
            ],
          },
        },
      };

      const visibleChannels = sidebarChannelCategories({
        currentUser,
        router: {
          currentRoute: {
            attributes: {
              category: workspace,
            },
          },
        },
        site: {
          categoriesList: [workspace, firstChannel, secondChannel],
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
              currentUserMembership: { following: true },
            },
          ],
        },
      });

      assert.deepEqual(visibleChannels, [secondChannel, firstChannel]);
      assert.deepEqual(workspaceSidebarSectionChannelOrder(currentUser, 40), [
        42,
        41,
      ]);
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

    test("detects chat unread state from tracking counters", function (assert) {
      assert.true(
        chatChannelHasUnread({
          tracking: {
            unreadCount: 1,
            mentionCount: 0,
            watchedThreadsUnreadCount: 0,
          },
        })
      );

      assert.true(
        chatChannelHasUnread({
          tracking: {
            unreadCount: 0,
            mentionCount: 1,
            watchedThreadsUnreadCount: 0,
          },
        })
      );

      assert.true(
        chatChannelHasUnread({
          tracking: {
            unreadCount: 0,
            mentionCount: 0,
            watchedThreadsUnreadCount: 1,
          },
        })
      );

      assert.true(
        chatChannelHasUnread({
          unreadThreadsCountSinceLastViewed: 1,
          tracking: {
            unreadCount: 0,
            mentionCount: 0,
            watchedThreadsUnreadCount: 0,
          },
        })
      );

      assert.false(
        chatChannelHasUnread({
          tracking: {
            unreadCount: 0,
            mentionCount: 0,
            watchedThreadsUnreadCount: 0,
          },
        })
      );
    });

    test("does not infer chat unread state from hydrated message data", function (assert) {
      assert.false(
        chatChannelHasUnread({
          last_message: { id: 2159639 },
          current_user_membership: {
            last_read_message_id: null,
          },
        })
      );
    });

    test("persists the unread-only sidebar preference", function (assert) {
      writeWorkspaceUnreadFilter(true);
      assert.true(readWorkspaceUnreadFilter());
      assert.strictEqual(localStorage.getItem(WORKSPACE_UNREAD_FILTER_KEY), "true");

      writeWorkspaceUnreadFilter(false);
      assert.false(readWorkspaceUnreadFilter());
      assert.strictEqual(localStorage.getItem(WORKSPACE_UNREAD_FILTER_KEY), "false");
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
          currentUser: { groups: [{ id: 400 }] },
          site: { categoriesList: [workspace, channel] },
          siteSettings: {},
        }),
        workspace
      );

      assert.deepEqual(
        sidebarScopedCategories({
          currentUser: { groups: [{ id: 400 }] },
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

    test("only reports a focused workspace when the workspace focus key is set", function (assert) {
      const workspace = {
        id: 20,
        parent_category_id: null,
        workspace_kind: "workspace",
        workspace_group_id: 220,
      };

      const services = {
        currentUser: { groups: [{ id: 220 }] },
        site: { categoriesList: [workspace] },
        siteSettings: {},
      };

      assert.strictEqual(
        rememberedOrDefaultWorkspaceCategory(services),
        workspace
      );
      assert.strictEqual(focusedWorkspaceCategory(services), null);

      sessionStorage.setItem(WORKSPACE_FOCUS_KEY, "20");

      assert.strictEqual(focusedWorkspaceCategory(services), workspace);

      sessionStorage.setItem(WORKSPACE_FOCUS_KEY, "999");

      assert.strictEqual(focusedWorkspaceCategory(services), null);
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
