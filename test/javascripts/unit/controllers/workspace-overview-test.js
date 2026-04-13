import { module, test } from "qunit";
import sinon from "sinon";
import pretender from "discourse/tests/helpers/create-pretender";
import { setupTest } from "discourse/tests/helpers/index";

module(
  "Discourse Workspace Groups | Controller | workspace-overview",
  function (hooks) {
    setupTest(hooks);

    hooks.afterEach(function () {
      sinon.restore();
    });

    test("prompts before leaving a private channel", async function (assert) {
      const controller = this.owner.lookup("controller:discovery.workspaceOverview");
      controller.model = { category: { id: 28 }, channels: [] };

      const chatChannelsManager = this.owner.lookup("service:chat-channels-manager");
      sinon.stub(chatChannelsManager, "remove");

      pretender.delete(
        "/workspace-groups/workspaces/28/channels/29/membership",
        () => [
          200,
          { "Content-Type": "application/json" },
          JSON.stringify({
            channel: {
              id: 29,
              visible: true,
              can_leave: false,
              can_join: true,
            },
          }),
        ]
      );

      const confirm = sinon
        .stub(controller.dialog, "confirm")
        .resolves(true);

      const channel = {
        id: 29,
        name: "Secure Lab",
        visibility: "private",
        is_pending: false,
      };

      await controller.leaveChannel(channel);

      assert.true(confirm.calledOnce);
      assert.strictEqual(
        confirm.firstCall.args[0].message,
        "Leave Secure Lab? You will need an invitation to rejoin this private channel."
      );
      assert.false(channel.is_pending);
      assert.true(channel.can_join);
      assert.false(channel.can_leave);
    });

    test("leaves a public channel without confirmation", async function (assert) {
      const controller = this.owner.lookup("controller:discovery.workspaceOverview");
      controller.model = { category: { id: 28 }, channels: [] };

      const chatChannelsManager = this.owner.lookup("service:chat-channels-manager");
      sinon.stub(chatChannelsManager, "remove");
      const confirm = sinon.stub(controller.dialog, "confirm");

      pretender.delete(
        "/workspace-groups/workspaces/28/channels/30/membership",
        () => [
          200,
          { "Content-Type": "application/json" },
          JSON.stringify({
            channel: {
              id: 30,
              visible: true,
              can_leave: false,
              can_join: true,
            },
          }),
        ]
      );

      const channel = {
        id: 30,
        name: "Public Lab",
        visibility: "public",
        is_pending: false,
      };

      await controller.leaveChannel(channel);

      assert.true(confirm.notCalled);
      assert.true(channel.can_join);
      assert.false(channel.can_leave);
    });
  }
);
