import Service from "@ember/service";
import { click, visit } from "@ember/test-helpers";
import { test } from "qunit";
import {
  acceptance,
  updateCurrentUser,
} from "discourse/tests/helpers/qunit-helpers";

class ChatServiceStub extends Service {
  activeChannel = null;

  async loadChannels() {}
}

class ChatChannelsManagerStub extends Service {
  channels = [];

  find() {}

  store(channel) {
    return channel;
  }
}

class WorkspaceVoiceStub extends Service {
  channels = [];
  loadFailed = false;

  async refresh() {}
}

acceptance("Discourse Workspace Groups | Load errors", function (needs) {
  let hydrationRequests = 0;
  let hydrationFails = true;
  let archivedFails = true;

  needs.user();
  needs.settings({
    discourse_workspace_groups_enabled: true,
    navigation_menu: "sidebar",
  });
  needs.site({
    categories: [
      {
        id: 28,
        name: "Quantum",
        slug: "quantum",
        workspace_kind: "workspace",
        permission: 1,
      },
      {
        id: 29,
        name: "Lab",
        slug: "lab",
        parent_category_id: 28,
        workspace_kind: "channel",
        permission: 1,
      },
    ],
  });

  needs.hooks.beforeEach(function () {
    hydrationRequests = 0;
    hydrationFails = true;
    archivedFails = true;
  });

  needs.pretender((server, helper) => {
    server.get("/workspace-groups/workspaces/28.json", () =>
      helper.response({
        workspace: { id: 28, name: "Quantum" },
        channels: [],
        archived_channel_count: 1,
      })
    );
    server.get("/workspace-groups/workspaces/28", () => {
      hydrationRequests += 1;

      return hydrationFails
        ? helper.response(500, { errors: ["boom"] })
        : helper.response({ channels: [] });
    });
    server.get("/workspace-groups/workspaces/28/archived-channels.json", () =>
      archivedFails
        ? helper.response(500, { errors: ["boom"] })
        : helper.response({
            channels: [
              {
                id: 30,
                name: "Old Lab",
                archived: true,
                visibility: "public",
              },
            ],
          })
    );
    server.get("/workspace-groups/workspaces/28/chat-tracking", () =>
      helper.response({ channel_tracking: {} })
    );
  });

  function registerServiceStubs(owner) {
    // Chat and Voice are not part of this plugin's test build; the
    // application boots on visit.
    owner.register("service:workspace-voice", WorkspaceVoiceStub);
    owner.register("service:chat", ChatServiceStub);
    owner.register("service:chat-channels-manager", ChatChannelsManagerStub);
    updateCurrentUser({ visibleGroups: [{ id: 1, name: "quantum" }] });
  }

  test("retries failed chat hydration and then offers a manual retry", async function (assert) {
    registerServiceStubs(this.owner);

    await visit("/c/quantum/28/overview");

    assert.strictEqual(
      hydrationRequests,
      4,
      "the initial load is retried three times with backoff"
    );
    assert
      .dom(".workspace-team-sidebar__load-error")
      .includesText(
        "Chat status for this workspace's channels could not be loaded."
      );

    hydrationFails = false;
    await click(".workspace-team-sidebar__load-error-retry");

    assert.strictEqual(hydrationRequests, 5);
    assert.dom(".workspace-team-sidebar__load-error").doesNotExist();
  });

  test("shows a retryable error when archived channels fail to load", async function (assert) {
    registerServiceStubs(this.owner);
    hydrationFails = false;

    await visit("/c/quantum/28/overview");
    await click(".workspace-groups-overview__archived-summary");

    assert
      .dom(".workspace-groups-overview__archived-error")
      .includesText("Archived channels could not be loaded.");

    archivedFails = false;
    await click(".workspace-groups-overview__archived-retry");

    assert.dom(".workspace-groups-overview__archived-error").doesNotExist();
    assert
      .dom(".workspace-groups-overview__channels--archived")
      .includesText("Old Lab");
  });
});
