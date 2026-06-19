import { module, test } from "qunit";
import {
  internalWorkspaceCandidatePath,
  targetAfterJoin,
} from "discourse/plugins/discourse-workspace-groups/discourse/api-initializers/workspace-joinable-channel-navigation";

module(
  "Discourse Workspace Groups | Unit | workspace-joinable-channel-navigation",
  function () {
    test("detects same-origin category, topic, and chat links", function (assert) {
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

      const chatLink = document.createElement("a");
      chatLink.href = "/chat/c/team-channel-42/7";

      assert.deepEqual(internalWorkspaceCandidatePath(chatLink), {
        target: "/chat/c/team-channel-42/7",
        resolverPath: "/chat/c/team-channel-42/7",
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

    test("routes joined chat-only channels to chat", function (assert) {
      assert.strictEqual(
        targetAfterJoin(
          { target: "/c/team/channel/42" },
          {
            mode: "chat_only",
            chat_channel_id: 7,
            chat_channel: { slug: "team-channel-42" },
          }
        ),
        "/chat/c/team-channel-42/7"
      );

      assert.strictEqual(
        targetAfterJoin(
          { target: "/c/team/channel/42" },
          { mode: "chat_only", chat_channel_id: 7 }
        ),
        "/chat/c/-/7"
      );

      assert.strictEqual(
        targetAfterJoin(
          { target: "/c/team/channel/42" },
          { mode: "combined", chat_channel_id: 7 }
        ),
        "/c/team/channel/42"
      );
    });
  }
);
