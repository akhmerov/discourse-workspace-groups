import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import selectKit from "discourse/tests/helpers/select-kit-helper";
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
      assert
        .dom(".workspace-groups-channel-members-modal__empty")
        .doesNotExist();

      await click(".workspace-groups-channel-members-modal__retry");

      assert.strictEqual(requests, 2);
      assert
        .dom(".workspace-groups-channel-members-modal__error")
        .doesNotExist();
      assert
        .dom(".workspace-groups-channel-members-modal__username")
        .hasText("alice");
    });

    test("shows external candidates, selects them, and submits their username", async function (assert) {
      const accessUrl =
        "/workspace-groups/workspaces/28/channels/29/access.json";
      const channel = { id: 29, name: "Lab", can_add_members: true };
      const currentMember = { id: 1, username: "alice" };
      const external = {
        id: 3,
        username: "victormp",
        name: "Victor",
        avatar_template: "/letter_avatar_proxy/v4/letter/v/123456/{size}.png",
        external: true,
      };
      let searchCount = 0;
      let submitted = false;
      pretender.get(accessUrl, () =>
        response({ channel, members: [currentMember] })
      );
      pretender.get(
        `${accessUrl.replace(".json", "")}/search.json`,
        (request) => {
          searchCount += 1;
          assert.strictEqual(request.queryParams.term, "victor");
          return response({
            users: [
              {
                id: 2,
                username: "victor_team",
                avatar_template: external.avatar_template,
                external: false,
              },
              external,
            ],
          });
        }
      );
      pretender.post(accessUrl, (request) => {
        submitted = true;
        assert.strictEqual(
          new URLSearchParams(request.requestBody).get("usernames"),
          "victormp"
        );
        return response({ channel, members: [currentMember, external] });
      });
      this.model = {
        category: { id: 28 },
        workspace: { group_name: "team" },
        channel,
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

      const picker = selectKit(".user-chooser");
      await picker.expand();
      assert.strictEqual(searchCount, 0, "blank search has no suggestions");
      await picker.fillInFilter("@victor");
      assert.strictEqual(picker.rowByIndex(0).value(), "victor_team");
      assert
        .dom(
          ".select-kit-row[data-value='victor_team'] .workspace-groups-member-external"
        )
        .doesNotExist();
      assert
        .dom(
          ".select-kit-row[data-value='victormp'] .workspace-groups-member-external"
        )
        .hasText("external");
      await picker.selectRowByValue("victormp");
      assert
        .dom(".workspace-groups-channel-members-modal__add .btn-primary")
        .isEnabled();
      await click(".workspace-groups-channel-members-modal__add .btn-primary");
      assert.true(submitted);
      assert
        .dom(".workspace-groups-channel-members-modal__member")
        .exists({ count: 2 });
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
      assert
        .dom(".workspace-groups-channel-members-modal__error")
        .doesNotExist();
    });
  }
);
