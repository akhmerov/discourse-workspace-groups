import { click, fillIn, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender from "discourse/tests/helpers/create-pretender";
import ManageWorkspaceChannelAccessModal from "discourse/plugins/discourse-workspace-groups/discourse/components/modal/manage-workspace-channel-access";

module(
  "Discourse Workspace Groups | Component | manage-workspace-channel-access",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      this.closeModal = sinon.spy();
      this.onChannelUpdate = sinon.spy();
    });

    hooks.afterEach(function () {
      sinon.restore();
    });

    test("loads members and updates channel access without leaving the overview", async function (assert) {
      let addRequestBody;
      let removedUrl;

      pretender.get("/workspace-groups/workspaces/28/channels/29/access", () => [
        200,
        { "Content-Type": "application/json" },
        JSON.stringify({
          channel: { id: 29, member_count: 1 },
          members: [
            {
              id: 11,
              username: "ada",
              name: "Ada",
              owner: true,
              guest: false,
              can_remove: false,
            },
          ],
        }),
      ]);

      pretender.post("/workspace-groups/workspaces/28/channels/29/access", (request) => {
        addRequestBody = request.requestBody;

        return [
          200,
          { "Content-Type": "application/json" },
          JSON.stringify({
            channel: { id: 29, member_count: 2 },
            members: [
              {
                id: 11,
                username: "ada",
                name: "Ada",
                owner: true,
                guest: false,
                can_remove: false,
              },
              {
                id: 22,
                username: "guest",
                name: "Guest User",
                owner: false,
                guest: true,
                can_remove: true,
              },
            ],
          }),
        ];
      });

      pretender.delete("/workspace-groups/workspaces/28/channels/29/access/22", (request) => {
        removedUrl = request.url;

        return [
          200,
          { "Content-Type": "application/json" },
          JSON.stringify({
            channel: { id: 29, member_count: 1 },
            members: [
              {
                id: 11,
                username: "ada",
                name: "Ada",
                owner: true,
                guest: false,
                can_remove: false,
              },
            ],
          }),
        ];
      });

      this.model = {
        category: { id: 28 },
        channel: { id: 29, name: "Lab Notes" },
        onChannelUpdate: this.onChannelUpdate,
      };

      await render(
        <template>
          <ManageWorkspaceChannelAccessModal
            @inline={{true}}
            @model={{this.model}}
            @closeModal={{this.closeModal}}
          />
        </template>
      );

      await settled();

      assert.dom(".workspace-groups-channel-access-modal__member-name").hasText("@ada");
      assert.true(this.onChannelUpdate.calledWithMatch({ id: 29, member_count: 1 }));

      await fillIn(".workspace-groups-channel-access-modal__input", "guest");
      await click(".workspace-groups-channel-access-modal__add-button");

      assert.true(addRequestBody.includes("usernames=guest"));
      assert.dom(".workspace-groups-channel-access-modal__member-name").exists({ count: 2 });
      assert
        .dom(".workspace-groups-channel-access-modal__members")
        .includesText("@guest");
      assert.true(this.onChannelUpdate.calledWithMatch({ id: 29, member_count: 2 }));

      await click(".workspace-groups-channel-access-modal__remove-button");

      assert.true(
        removedUrl.endsWith("/workspace-groups/workspaces/28/channels/29/access/22")
      );
      assert.dom(".workspace-groups-channel-access-modal__member-name").exists({ count: 1 });
      assert.false(
        this.element
          .querySelector(".workspace-groups-channel-access-modal__members")
          .textContent.includes("@guest")
      );
      assert.true(this.onChannelUpdate.calledWithMatch({ id: 29, member_count: 1 }));
    });
  }
);
