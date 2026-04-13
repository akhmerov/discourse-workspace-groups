import { module, test } from "qunit";
import pretender from "discourse/tests/helpers/create-pretender";
import { setupTest } from "discourse/tests/helpers/index";

module(
  "Discourse Workspace Groups | Controller | workspace-overview lazy load",
  function (hooks) {
    setupTest(hooks);

    test("loads archived channels only once when the section is opened", async function (assert) {
      const controller = this.owner.lookup("controller:discovery.workspaceOverview");
      let requests = 0;

      controller.model = {
        category: { id: 28 },
        archivedChannels: [],
        archivedChannelCount: 2,
        archivedChannelsLoaded: false,
        archivedChannelsLoading: false,
      };

      pretender.get("/workspace-groups/workspaces/28/archived-channels.json", () => {
        requests += 1;

        return [
          200,
          { "Content-Type": "application/json" },
          JSON.stringify({
            channels: [
              { id: 31, name: "Archive", archived: true, visibility: "public" },
            ],
          }),
        ];
      });

      await controller.loadArchivedChannels({ target: { open: true } });
      await controller.loadArchivedChannels({ target: { open: true } });

      assert.strictEqual(requests, 1);
      assert.true(controller.model.archivedChannelsLoaded);
      assert.false(controller.model.archivedChannelsLoading);
      assert.strictEqual(controller.model.archivedChannels.length, 1);
      assert.strictEqual(controller.model.archivedChannels[0].id, 31);
      assert.false(controller.model.archivedChannels[0].is_pending);
    });
  }
);
