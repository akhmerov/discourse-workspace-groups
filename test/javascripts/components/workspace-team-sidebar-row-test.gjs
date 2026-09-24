import Service from "@ember/service";
import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import DiscourseURL from "discourse/lib/url";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import WorkspaceTeamSidebarRow from "discourse/plugins/discourse-workspace-groups/discourse/components/workspace-team-sidebar-row";

module(
  "Discourse Workspace Groups | Component | workspace-team-sidebar-row",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      class ChatStateManagerStub extends Service {
        prefersFullPage = sinon.spy();
      }

      class WorkspaceVoiceStub extends Service {
        channels = [];
      }
      class VoiceRoomsStub extends Service {
        rooms = [];
      }
      this.owner.register("service:workspace-voice", WorkspaceVoiceStub);
      this.owner.register("service:voice-rooms", VoiceRoomsStub);
      this.owner.register(
        "service:chat-state-manager",
        ChatStateManagerStub
      );
    });

    hooks.afterEach(function () {
      sinon.restore();
    });

        test("highlights only the mic when viewing a channel Voice room", async function (assert) {
          class WorkspaceVoiceStub extends Service {
            channels = [{ category_id: 29, room: { id: 7 } }];
          }
          class VoiceRoomsStub extends Service {
            rooms = [{ id: 7, active_participants: [{ id: 1 }] }];
          }
          this.owner.register("service:workspace-voice", WorkspaceVoiceStub);
          this.owner.register("service:voice-rooms", VoiceRoomsStub);
          this.categoryLink = {
            category: { id: 29 }, name: "lab-notes", route: "discovery.category",
            model: "quantum-tinkerer/lab-notes/29", currentWhen: "discovery.category",
            title: "Lab Notes", text: "Lab Notes", prefixType: "icon", prefixValue: "folder",
          };
          await render(<template>
            <WorkspaceTeamSidebarRow
              @categoryActive={{false}}
              @categoryLink={{this.categoryLink}}
              @chatActive={{false}}
              @chatPath="/chat/c/lab-notes/15"
              @voiceActive={{true}}
            />
          </template>);
          assert.dom(".workspace-voice-channel-link").hasClass("workspace-team-sidebar__mode-button--active");
          assert.dom(".workspace-voice-channel-link").hasAttribute("aria-current", "page");
          assert.dom(".workspace-team-sidebar__mode-button--active").exists({ count: 1 });
          assert.dom(".workspace-team-sidebar__main-link").doesNotHaveClass("active");
          assert.dom(".workspace-voice-channel-count").hasText("1");
        });


    test("opens chat-only channels through a real link", async function (assert) {
      sinon.stub(DiscourseURL, "routeTo");
      this.categoryLink = {
        category: { id: 29 },
        name: "chat-first",
        route: "discovery.category",
        model: "quantum-tinkerer/chat-first/29",
        title: "Chat First",
        text: "Chat First",
        prefixType: "icon",
        prefixValue: "folder",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryAvailable={{false}}
            @categoryLink={{this.categoryLink}}
            @chatAvailable={{true}}
            @chatPath="/chat/c/chat-first/15"
            @chatTitle="Open Chat First chat"
          />
        </template>
      );

      assert
        .dom("a.workspace-team-sidebar__main-link")
        .hasAttribute("href", "/chat/c/chat-first/15");

      await click("a.workspace-team-sidebar__main-link", { ctrlKey: true });
      assert.true(DiscourseURL.routeTo.notCalled, "leaves modified clicks to the browser");

      await click("a.workspace-team-sidebar__main-link");
      assert.true(DiscourseURL.routeTo.calledOnceWith("/chat/c/chat-first/15"));
    });

    test("marks the whole row of the active channel", async function (assert) {
      this.categoryLink = {
        category: { id: 29 },
        name: "chat-first",
        route: "discovery.category",
        model: "quantum-tinkerer/chat-first/29",
        title: "Chat First",
        text: "Chat First",
        prefixType: "icon",
        prefixValue: "folder",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryAvailable={{false}}
            @categoryLink={{this.categoryLink}}
            @chatActive={{true}}
            @chatAvailable={{true}}
            @chatPath="/chat/c/chat-first/15"
            @isActive={{true}}
          />
        </template>
      );

      assert
        .dom(".workspace-team-sidebar__row")
        .hasClass("workspace-team-sidebar__row--active");
      assert
        .dom("a.workspace-team-sidebar__main-link")
        .hasAttribute("aria-current", "page");
    });

    test("routes chat icon clicks without a full reload", async function (assert) {
      sinon.stub(DiscourseURL, "routeTo");

      this.categoryLink = {
        name: "lab-notes",
        route: "discovery.category",
        model: "quantum-tinkerer/lab-notes/29",
        currentWhen: "discovery.category",
        title: "Lab Notes",
        text: "Lab Notes",
        prefixType: "icon",
        prefixValue: "folder",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Lab Notes topics"
            @chatPath="/chat/c/lab-notes/15"
            @chatTitle="Open Lab Notes chat"
            @chatUnread={{true}}
            @categoryUnread={{false}}
            @isActive={{true}}
            @categoryActive={{false}}
            @chatActive={{true}}
          />
        </template>
      );

      await click(".workspace-team-sidebar__mode-button:last-child");

      const chatStateManager = this.owner.lookup("service:chat-state-manager");

      assert.true(chatStateManager.prefersFullPage.calledOnce);
      assert.true(DiscourseURL.routeTo.calledOnceWith("/chat/c/lab-notes/15"));
    });

    test("highlights the channel in chat mode and marks the chat button as the current page", async function (assert) {
      this.categoryLink = {
        name: "lab-notes",
        route: "discovery.category",
        model: "quantum-tinkerer/lab-notes/29",
        currentWhen: "discovery.category",
        title: "Lab Notes",
        text: "Lab Notes",
        prefixType: "square",
        prefixValue: ["2563EB"],
        prefixColor: "2563EB",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Lab Notes topics"
            @chatPath="/chat/c/lab-notes/15"
            @chatTitle="Open Lab Notes chat"
            @chatUnread={{false}}
            @categoryUnread={{false}}
            @isActive={{true}}
            @categoryActive={{false}}
            @chatActive={{true}}
          />
        </template>
      );

      assert.dom(".workspace-team-sidebar__main-link").hasClass("active");
      assert
        .dom(".workspace-team-sidebar__main-link")
        .doesNotHaveAttribute("aria-current");
      assert.dom(".workspace-team-sidebar__mode-button").doesNotHaveClass(
        "workspace-team-sidebar__mode-button--active"
      );
      assert
        .dom(".workspace-team-sidebar__mode-button:last-child")
        .hasClass("workspace-team-sidebar__mode-button--active")
        .hasAttribute("aria-current", "page");
    });

    test("does not highlight other channels on category pages", async function (assert) {
      this.categoryLink = {
        name: "lab-notes",
        route: "discovery.category",
        model: "quantum-tinkerer/lab-notes/29",
        currentWhen: "discovery.category",
        title: "Lab Notes",
        text: "Lab Notes",
        prefixType: "icon",
        prefixValue: "folder",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryActive={{false}}
            @categoryLink={{this.categoryLink}}
            @chatPath="/chat/c/lab-notes/15"
            @isActive={{false}}
          />
        </template>
      );

      assert.dom(".workspace-team-sidebar__main-link").doesNotHaveClass("active");
      assert
        .dom(".workspace-team-sidebar__mode-button:first-child")
        .doesNotHaveClass("active");
    });

    test("uses a calendar icon for event-enabled topic channels", async function (assert) {
      this.siteSettings.events_calendar_categories = "29";
      this.category = { id: 29 };
      this.categoryLink = {
        name: "lab-events",
        route: "discovery.category",
        model: "quantum-tinkerer/lab-events/29",
        currentWhen: "discovery.category",
        title: "Lab Events",
        text: "Lab Events",
        prefixType: "icon",
        prefixValue: "folder",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @category={{this.category}}
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Lab Events topics"
            @chatPath="/chat/c/lab-events/15"
            @chatTitle="Open Lab Events chat"
          />
        </template>
      );

      assert.dom(".workspace-team-sidebar__modes .d-icon-calendar-day").exists();
      assert.dom(".workspace-team-sidebar__modes .d-icon-list").doesNotExist();
    });

    test("renders muted rows with muted styling", async function (assert) {
      this.categoryLink = {
        name: "lab-notes",
        route: "discovery.category",
        model: "quantum-tinkerer/lab-notes/29",
        currentWhen: "discovery.category",
        title: "Lab Notes",
        text: "Lab Notes",
        prefixType: "icon",
        prefixValue: "folder",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Lab Notes topics"
            @chatPath="/chat/c/lab-notes/15"
            @chatTitle="Open Lab Notes chat"
            @chatUnread={{false}}
            @chatMuted={{true}}
            @categoryUnread={{false}}
            @isActive={{false}}
            @categoryActive={{false}}
            @chatActive={{false}}
          />
        </template>
      );

      assert
        .dom(".workspace-team-sidebar__main-link")
        .hasClass("sidebar-section-link--muted");
      assert
        .dom(".workspace-team-sidebar__mode-button")
        .hasClass("workspace-team-sidebar__mode-button--muted");
    });

    test("renders a draggable non-interactive row in sidebar edit mode", async function (assert) {
      this.categoryLink = {
        category: { id: 29 },
        name: "lab-notes",
        route: "discovery.category",
        model: "quantum-tinkerer/lab-notes/29",
        currentWhen: "discovery.category",
        title: "Lab Notes",
        text: "Lab Notes",
        prefixType: "icon",
        prefixValue: "folder",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Lab Notes topics"
            @chatPath="/chat/c/lab-notes/15"
            @chatTitle="Open Lab Notes chat"
            @editable={{true}}
          />
        </template>
      );

      assert.dom(".workspace-team-sidebar__drag-handle").doesNotExist();
      assert.dom(".workspace-team-sidebar__row--editing").exists();
      assert.dom(".workspace-team-sidebar__main-link--editing").exists();
      assert.dom(".workspace-team-sidebar__modes button").doesNotExist();
    });

    test("hides the lock badge for public workspace channels", async function (assert) {
      this.categoryLink = {
        category: { id: 29, workspace_visibility: "public" },
        name: "lab-notes",
        route: "discovery.category",
        model: "quantum-tinkerer/lab-notes/29",
        currentWhen: "discovery.category",
        title: "Lab Notes",
        text: "Lab Notes",
        prefixType: "icon",
        prefixValue: "folder",
        prefixBadge: "category.restricted",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Lab Notes topics"
            @chatPath="/chat/c/lab-notes/15"
            @chatTitle="Open Lab Notes chat"
          />
        </template>
      );

      assert.dom(".workspace-team-sidebar__main-link .prefix-badge").doesNotExist();
    });

    test("hides duplicate mode buttons when only one surface is available", async function (assert) {
      this.categoryLink = {
        category: { id: 29 },
        name: "chat-first",
        route: "discovery.category",
        model: "quantum-tinkerer/chat-first/29",
        currentWhen: "discovery.category",
        title: "Chat First",
        text: "Chat First",
        prefixType: "icon",
        prefixValue: "folder",
        prefixColor: "2563EB",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Chat First topics"
            @chatPath="/chat/c/chat-first/15"
            @chatTitle="Open Chat First chat"
            @chatUnread={{true}}
            @categoryAvailable={{false}}
            @chatAvailable={{true}}
          />
        </template>
      );

      assert.dom(".workspace-team-sidebar__modes").doesNotExist();
      assert
        .dom(".workspace-team-sidebar__main-link-prefix .d-icon-d-chat")
        .exists();
      assert
        .dom(".workspace-team-sidebar__main-link-prefix .sidebar-section-link-prefix")
        .hasStyle({ color: "rgb(37, 99, 235)" });
      assert
        .dom(".workspace-team-sidebar__main-link")
        .hasClass("workspace-team-sidebar__main-link--compact");
      assert
        .dom(
          ".workspace-team-sidebar__main-link-prefix .chat-channel-unread-indicator"
        )
        .exists();
      assert
        .dom(".workspace-team-sidebar__main-link")
        .hasClass("workspace-team-sidebar__main-link--unread");
    });

    test("keeps emoji prefix for chat-only rows with category emoji", async function (assert) {
      this.categoryLink = {
        category: { id: 29, emoji: "rocket" },
        name: "chat-first",
        route: "discovery.category",
        model: "quantum-tinkerer/chat-first/29",
        currentWhen: "discovery.category",
        title: "Chat First",
        text: "Chat First",
        prefixType: "emoji",
        prefixValue: "rocket",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Chat First topics"
            @chatPath="/chat/c/chat-first/15"
            @chatTitle="Open Chat First chat"
            @categoryAvailable={{false}}
            @chatAvailable={{true}}
          />
        </template>
      );

      assert
        .dom(".workspace-team-sidebar__main-link-prefix .d-icon-d-chat")
        .doesNotExist();
      assert.dom(".workspace-team-sidebar__main-link-prefix img.emoji").exists();
    });

    test("shows unread state on the main icon for category-only rows", async function (assert) {
      this.categoryLink = {
        name: "forum-first",
        route: "discovery.category",
        model: "quantum-tinkerer/forum-first/29",
        currentWhen: "discovery.category",
        title: "Forum First",
        text: "Forum First",
        prefixType: "square",
        prefixValue: ["2563EB"],
        prefixColor: "2563EB",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Forum First topics"
            @chatPath={{null}}
            @chatTitle="Open Forum First chat"
            @categoryUnread={{true}}
            @categoryAvailable={{true}}
            @chatAvailable={{false}}
          />
        </template>
      );

      assert.dom(".workspace-team-sidebar__modes").doesNotExist();
      assert
        .dom(
          ".workspace-team-sidebar__main-link-prefix .chat-channel-unread-indicator"
        )
        .exists();
      assert
        .dom(".workspace-team-sidebar__main-link")
        .hasClass("workspace-team-sidebar__main-link--unread");
    });

    test("keeps unread state on mode icons when both surfaces are available", async function (assert) {
      this.categoryLink = {
        name: "mixed",
        route: "discovery.category",
        model: "quantum-tinkerer/mixed/29",
        currentWhen: "discovery.category",
        title: "Mixed",
        text: "Mixed",
        prefixType: "icon",
        prefixValue: "folder",
      };

      await render(
        <template>
          <WorkspaceTeamSidebarRow
            @categoryLink={{this.categoryLink}}
            @categoryTitle="Open Mixed topics"
            @chatPath="/chat/c/mixed/15"
            @chatTitle="Open Mixed chat"
            @chatUnread={{true}}
            @categoryUnread={{true}}
            @categoryAvailable={{true}}
            @chatAvailable={{true}}
          />
        </template>
      );

      assert.dom(".workspace-team-sidebar__modes").exists();
      assert
        .dom(
          ".workspace-team-sidebar__main-link-prefix .chat-channel-unread-indicator"
        )
        .exists();
      assert
        .dom(".workspace-team-sidebar__mode-icon .chat-channel-unread-indicator")
        .exists({ count: 2 });
      assert
        .dom(".workspace-team-sidebar__main-link")
        .hasClass("workspace-team-sidebar__main-link--unread");
    });
  }
);
