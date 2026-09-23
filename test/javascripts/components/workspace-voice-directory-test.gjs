import Service from "@ember/service";
import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import WorkspaceVoiceDirectory from "discourse/plugins/discourse-workspace-groups/discourse/components/workspace-voice-directory";

module(
  "Discourse Workspace Groups | Component | workspace-voice-directory",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      class VoiceRoomsStub extends Service {
        rooms = [];

        roomById() {}
      }
      class VoiceWebrtcStub extends Service {
        activeRoomId = null;
      }
      this.owner.register("service:voice-rooms", VoiceRoomsStub);
      this.owner.register("service:voice-webrtc", VoiceWebrtcStub);
    });

    test("distinguishes a failed load from an empty directory", async function (assert) {
      let refreshes = 0;
      class WorkspaceVoiceStub extends Service {
        channels = [];
        loadFailed = true;

        async refresh() {
          refreshes += 1;
          throw new Error("still failing");
        }
      }
      this.owner.register("service:workspace-voice", WorkspaceVoiceStub);

      await render(<template><WorkspaceVoiceDirectory /></template>);

      assert
        .dom(".workspace-voice-directory__error")
        .includesText("Voice rooms could not be loaded.");
      assert
        .dom(".workspace-voice-directory")
        .doesNotIncludeText("No voice rooms are enabled");

      await click(".workspace-voice-directory__retry");

      assert.strictEqual(refreshes, 1);
      assert.dom(".workspace-voice-directory__error").exists();
      assert.dom(".workspace-voice-directory__retry").isNotDisabled();
    });

    test("shows the empty message when no rooms are enabled", async function (assert) {
      class WorkspaceVoiceStub extends Service {
        channels = [];
        loadFailed = false;
      }
      this.owner.register("service:workspace-voice", WorkspaceVoiceStub);

      await render(<template><WorkspaceVoiceDirectory /></template>);

      assert.dom(".workspace-voice-directory__error").doesNotExist();
      assert
        .dom(".workspace-voice-directory")
        .includesText("No voice rooms are enabled");
    });
  }
);
