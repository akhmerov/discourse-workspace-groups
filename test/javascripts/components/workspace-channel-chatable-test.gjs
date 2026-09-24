import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import Category from "discourse/models/category";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import ChatFabricators from "discourse/plugins/chat/discourse/lib/fabricators";
import WorkspaceChannelChatable from "discourse/plugins/discourse-workspace-groups/discourse/components/workspace-channel-chatable";

module(
  "Discourse Workspace Groups | Component | workspace-channel-chatable",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.afterEach(function () {
      sinon.restore();
    });

    function itemFor(owner, chatable) {
      return {
        identifier: "c-1",
        type: "channel",
        enabled: true,
        model: new ChatFabricators(owner).channel({
          chatable: Category.create({
            id: 12,
            name: "Delft",
            read_restricted: true,
            ...chatable,
          }),
        }),
      };
    }

    test("names the team of a team channel and drops the lock on public ones", async function (assert) {
      sinon
        .stub(Category, "findById")
        .callsFake((id) => (id === 5 ? { id: 5, name: "Quantum team" } : null));
      this.item = itemFor(this.owner, {
        workspace_kind: "channel",
        workspace_parent_category_id: 5,
        workspace_visibility: "public",
      });

      await render(<template><WorkspaceChannelChatable @item={{this.item}} /></template>);

      assert
        .dom(".workspace-channel-chatable__team")
        .hasText("Quantum team");
      assert
        .dom(".workspace-channel-chatable")
        .hasClass("workspace-channel-chatable--public");
      assert.dom(".chat-message-creator__chatable").exists();
    });

    test("leaves other channels as core renders them", async function (assert) {
      this.item = itemFor(this.owner, {});

      await render(<template><WorkspaceChannelChatable @item={{this.item}} /></template>);

      assert.dom(".workspace-channel-chatable__team").doesNotExist();
      assert
        .dom(".workspace-channel-chatable")
        .doesNotHaveClass("workspace-channel-chatable--public");
    });
  }
);
