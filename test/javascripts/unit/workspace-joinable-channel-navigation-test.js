import { module, test } from "qunit";
import { internalWorkspaceCandidatePath } from "discourse/plugins/discourse-workspace-groups/discourse/api-initializers/workspace-joinable-channel-navigation";

module(
  "Discourse Workspace Groups | Unit | workspace-joinable-channel-navigation",
  function () {
    test("detects same-origin category and topic links", function (assert) {
      const categoryLink = document.createElement("a");
      categoryLink.href = "/c/team/channel/42?ascending=true#latest";

      assert.deepEqual(internalWorkspaceCandidatePath(categoryLink), {
        target: "/c/team/channel/42?ascending=true#latest",
        resolverPath: "/c/team/channel/42",
      });

      const topicLink = document.createElement("a");
      topicLink.href = "/t/welcome/99/3";

      assert.deepEqual(internalWorkspaceCandidatePath(topicLink), {
        target: "/t/welcome/99/3",
        resolverPath: "/t/welcome/99/3",
      });
    });

    test("ignores external, non-forum, and new-window links", function (assert) {
      const externalLink = document.createElement("a");
      externalLink.href = "https://example.com/c/team/channel/42";

      assert.strictEqual(internalWorkspaceCandidatePath(externalLink), null);

      const latestLink = document.createElement("a");
      latestLink.href = "/latest";

      assert.strictEqual(internalWorkspaceCandidatePath(latestLink), null);

      const newWindowLink = document.createElement("a");
      newWindowLink.href = "/c/team/channel/42";
      newWindowLink.target = "_blank";

      assert.strictEqual(internalWorkspaceCandidatePath(newWindowLink), null);
    });
  }
);
