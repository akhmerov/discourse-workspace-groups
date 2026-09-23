import Service from "@ember/service";
import { module, test } from "qunit";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { setupTest } from "discourse/tests/helpers/index";
import { logIn } from "discourse/tests/helpers/qunit-helpers";

module("Discourse Workspace Groups | Service | workspace-voice", function (hooks) {
  setupTest(hooks);

  hooks.beforeEach(function () {
    logIn(this.owner);

    class VoiceRoomsStub extends Service {
      ready = Promise.resolve();
      rooms = [];

      upsertRoom() {}

      handleDirectoryEvent() {}
    }
    class VoiceWebrtcStub extends Service {
      activeRoomId = null;
    }
    this.owner.register("service:voice-rooms", VoiceRoomsStub);
    this.owner.register("service:voice-webrtc", VoiceWebrtcStub);
    const siteSettings = this.owner.lookup("service:site-settings");
    siteSettings.voice_enabled = true;
    siteSettings.discourse_workspace_groups_enabled = true;
  });

  test("records a failed refresh until a later refresh succeeds", async function (assert) {
    let fail = true;
    pretender.get("/workspace-groups/voice/rooms.json", () =>
      fail
        ? response(500, { errors: ["boom"] })
        : response({ channels: [{ category_id: 29, name: "Lab" }] })
    );

    const voice = this.owner.lookup("service:workspace-voice");

    await assert.rejects(voice.refresh());
    assert.true(voice.loadFailed);
    assert.deepEqual(voice.channels, []);

    fail = false;
    await voice.refresh();

    assert.false(voice.loadFailed);
    assert.strictEqual(voice.channels.length, 1);
  });
});
