import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import Service from "@ember/service";
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

      this.owner.register(
        "service:chat-state-manager",
        ChatStateManagerStub
      );
    });

    hooks.afterEach(function () {
      sinon.restore();
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

    test("only marks the main link active in topic mode", async function (assert) {
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

      assert
        .dom(".workspace-team-sidebar__main-link")
        .doesNotHaveClass("active");
      assert.dom(".workspace-team-sidebar__mode-button").doesNotHaveClass(
        "workspace-team-sidebar__mode-button--active"
      );
      assert
        .dom(".workspace-team-sidebar__mode-button:last-child")
        .hasClass("workspace-team-sidebar__mode-button--active");
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

      assert.dom(".workspace-team-sidebar__drag-handle").exists();
      assert.dom(".workspace-team-sidebar__row--editing").exists();
      assert.dom(".workspace-team-sidebar__main-link--editing").exists();
      assert.dom(".workspace-team-sidebar__modes button").doesNotExist();
    });
  }
);
