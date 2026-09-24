import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import WorkspaceChannelSettingsModal from "discourse/plugins/discourse-workspace-groups/discourse/components/modal/workspace-channel-settings";

const MODAL = ".workspace-groups-channel-settings-modal";

function channel(overrides = {}) {
  return {
    id: 29,
    name: "Lab",
    description_raw: "Lab notes",
    visibility: "public",
    mode: "both",
    voice_enabled: true,
    voice_allow_guests: true,
    allow_channel_wide_mentions: true,
    color: "0088CC",
    style_type: "square",
    can_archive: true,
    can_edit_settings: true,
    can_manage_members: false,
    ...overrides,
  };
}

module(
  "Discourse Workspace Groups | Component | workspace-channel-settings",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      this.siteSettings.voice_enabled = true;
      this.siteSettings.category_colors = "0088CC";
      sinon.stub(this.owner.lookup("service:workspace-voice"), "refresh");
      this.closeModal = () => {};
    });

    hooks.afterEach(function () {
      sinon.restore();
    });

    test("members get the settings without manager-only fields", async function (assert) {
      let submitted;
      pretender.put("/workspace-groups/workspaces/28/channels/29", (request) => {
        submitted = new URLSearchParams(request.requestBody);
        return response({ channel: channel() });
      });

      this.model = {
        category: { id: 28 },
        workspace: { can_create_private_channel: true },
        channel: channel(),
      };

      await render(
        <template>
          <WorkspaceChannelSettingsModal
            @closeModal={{this.closeModal}}
            @inline={{true}}
            @model={{this.model}}
          />
        </template>
      );

      assert
        .dom(`${MODAL} .workspace-groups-create-channel-modal__input`)
        .doesNotExist("hides the name field");
      assert
        .dom(`${MODAL} .workspace-groups-create-channel-modal__textarea`)
        .hasValue("Lab notes");
      assert.dom(`${MODAL} .d-toggle-switch`).exists({ count: 2 }, "voice and events only");

      await click(`${MODAL} .btn-primary`);

      assert.strictEqual(submitted.get("name"), "Lab");
      assert.strictEqual(submitted.get("description"), "Lab notes");
      assert.false(submitted.has("visibility"));
      assert.false(submitted.has("voice_allow_guests"));
      assert.false(submitted.has("allow_channel_wide_mentions"));
    });

    test("managers keep every field", async function (assert) {
      this.model = {
        category: { id: 28 },
        workspace: { can_create_private_channel: true },
        channel: channel({ can_manage_members: true }),
      };

      await render(
        <template>
          <WorkspaceChannelSettingsModal
            @closeModal={{this.closeModal}}
            @inline={{true}}
            @model={{this.model}}
          />
        </template>
      );

      assert.dom(`${MODAL} .workspace-groups-create-channel-modal__input`).hasValue("Lab");
      assert
        .dom(`${MODAL} .d-toggle-switch`)
        .exists({ count: 5 }, "voice, guests, events, visibility, mentions");
    });
  }
);
