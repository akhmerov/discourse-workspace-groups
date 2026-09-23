import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import WorkspaceChannelMembersModal from "discourse/plugins/discourse-workspace-groups/discourse/components/modal/workspace-channel-members";

module(
  "Discourse Workspace Groups | Component | workspace-channel-members",
  function (hooks) {
    setupRenderingTest(hooks);

    test("shows an error with Retry instead of an empty list when loading fails", async function (assert) {
      let requests = 0;

      pretender.get(
        "/workspace-groups/workspaces/28/channels/29/access.json",
        () => {
          requests += 1;

          if (requests === 1) {
            return response(500, { errors: ["boom"] });
          }

          return response({
            channel: { id: 29, name: "Lab", can_add_members: false },
            members: [{ id: 1, username: "alice" }],
          });
        }
      );

      this.model = {
        category: { id: 28 },
        workspace: { group_name: "team" },
        channel: { id: 29, name: "Lab" },
      };

      await render(
        <template>
          <WorkspaceChannelMembersModal
            @inline={{true}}
            @model={{this.model}}
            @closeModal={{this.closeModal}}
          />
        </template>
      );

      assert
        .dom(".workspace-groups-channel-members-modal__error")
        .includesText("Channel members could not be loaded.");
      assert.dom(".workspace-groups-channel-members-modal__empty").doesNotExist();

      await click(".workspace-groups-channel-members-modal__retry");

      assert.strictEqual(requests, 2);
      assert.dom(".workspace-groups-channel-members-modal__error").doesNotExist();
      assert
        .dom(".workspace-groups-channel-members-modal__username")
        .hasText("alice");
    });

    test("shows the empty state when the channel has no members", async function (assert) {
      pretender.get(
        "/workspace-groups/workspaces/28/channels/29/access.json",
        () =>
          response({
            channel: { id: 29, name: "Lab", can_add_members: false },
            members: [],
          })
      );

      this.model = {
        category: { id: 28 },
        workspace: { group_name: "team" },
        channel: { id: 29, name: "Lab" },
      };

      await render(
        <template>
          <WorkspaceChannelMembersModal
            @inline={{true}}
            @model={{this.model}}
            @closeModal={{this.closeModal}}
          />
        </template>
      );

      assert
        .dom(".workspace-groups-channel-members-modal__empty")
        .hasText("No members yet.");
      assert.dom(".workspace-groups-channel-members-modal__error").doesNotExist();
    });
  }
);
