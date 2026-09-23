import Service from "@ember/service";
import { module, test } from "qunit";
import sinon from "sinon";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { setupTest } from "discourse/tests/helpers/index";
import { setupWorkspaceChatServices } from "../../helpers/setup-workspace-chat-services";

module(
  "Discourse Workspace Groups | Controller | workspace-overview",
  function (hooks) {
    setupTest(hooks);
    setupWorkspaceChatServices(hooks);

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

    test("treats the Voice refresh after a successful join as best-effort", async function (assert) {
      let voiceRefreshes = 0;
      class WorkspaceVoiceStub extends Service {
        async refresh() {
          voiceRefreshes += 1;
          throw new Error("Voice directory unavailable");
        }
      }
      this.owner.register("service:workspace-voice", WorkspaceVoiceStub);

      const controller = this.owner.lookup("controller:discovery.workspaceOverview");
      controller.model = { category: { id: 28 }, channels: [] };

      const chatChannelsManager = this.owner.lookup("service:chat-channels-manager");
      const storedChannel = { id: 55 };
      sinon.stub(chatChannelsManager, "store").returns(storedChannel);
      const follow = sinon.stub(chatChannelsManager, "follow").resolves();
      const alert = sinon.stub(controller.dialog, "alert");

      pretender.post(
        "/workspace-groups/workspaces/28/channels/29/membership",
        () =>
          response({
            channel: {
              id: 29,
              visible: true,
              can_join: false,
              can_leave: true,
              chat_channel: { id: 55 },
            },
          })
      );

      const channel = {
        id: 29,
        name: "Lab",
        visibility: "public",
        is_pending: false,
        can_join: true,
      };

      await controller.joinChannel(channel);

      assert.strictEqual(voiceRefreshes, 1);
      assert.true(alert.notCalled, "no join error is shown");
      assert.true(follow.calledOnceWith(storedChannel), "chat is still synced");
      assert.false(channel.can_join);
      assert.true(channel.can_leave);
      assert.false(channel.is_pending);
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
