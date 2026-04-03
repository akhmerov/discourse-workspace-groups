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
  }
);
