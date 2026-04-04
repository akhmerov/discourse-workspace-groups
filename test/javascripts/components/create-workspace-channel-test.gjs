import { click, fillIn, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import DiscourseURL from "discourse/lib/url";
import Category from "discourse/models/category";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender from "discourse/tests/helpers/create-pretender";
import CreateWorkspaceChannelModal from "discourse/plugins/discourse-workspace-groups/discourse/components/modal/create-workspace-channel";

module(
  "Discourse Workspace Groups | Component | create-workspace-channel",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      this.closeModal = sinon.spy();
    });

    hooks.afterEach(function () {
      sinon.restore();
    });

    test("routes to the new category without a hard reload", async function (assert) {
      sinon.stub(DiscourseURL, "routeTo");
      sinon.stub(Category, "asyncFindBySlugPathWithID").resolves();
      let requestBody;

      pretender.post("/workspace-groups/workspaces/28/channels", (request) => {
        requestBody = request.requestBody;

        return [
          200,
          { "Content-Type": "application/json" },
          JSON.stringify({ category_url: "/c/quantum-tinkerer/lab-notes/29" }),
        ];
      });

      this.model = { category: { id: 28 } };

      await render(
        <template>
          <CreateWorkspaceChannelModal
            @inline={{true}}
            @model={{this.model}}
            @closeModal={{this.closeModal}}
          />
        </template>
      );

      await fillIn(".workspace-groups-create-channel-modal__input", "Lab Notes");
      await click(".btn-primary");

      assert.true(this.closeModal.calledOnce);
      assert.true(
        Category.asyncFindBySlugPathWithID.calledOnceWith(
          "quantum-tinkerer/lab-notes/29"
        )
      );
      assert.true(
        DiscourseURL.routeTo.calledOnceWith("/c/quantum-tinkerer/lab-notes/29")
      );
      assert.false(requestBody.includes("usernames="));
    });

    test("does not render private member inputs", async function (assert) {
      this.model = { category: { id: 28 } };

      await render(
        <template>
          <CreateWorkspaceChannelModal
            @inline={{true}}
            @model={{this.model}}
            @closeModal={{this.closeModal}}
          />
        </template>
      );

      await click(".d-toggle-switch");

      assert
        .dom(".workspace-groups-create-channel-modal")
        .doesNotIncludeText("Initial members");
    });
  }
);
