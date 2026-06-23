import { module, test } from "qunit";
import {
  JOINABLE_CHANNEL_CHATABLE_TYPE,
  chatRouteModels,
  joinableChannelItems,
  sortWorkspaceChatables,
} from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-joinable-channel-chat-search";

module(
  "Discourse Workspace Groups | Unit | workspace-joinable-channel-chat-search",
  function () {
    test("dedupes channels already returned by native chat search", function (assert) {
      const nativeChatables = [{ type: "channel", model: { id: 10 } }];
      const channels = [
        { id: 1, chat_channel_id: 10 },
        { id: 2, chat_channel_id: 11, match_quality: 1 },
        { id: 3 },
      ];

      assert.deepEqual(joinableChannelItems(channels, nativeChatables), [
        {
          identifier: `${JOINABLE_CHANNEL_CHATABLE_TYPE}-2`,
          type: JOINABLE_CHANNEL_CHATABLE_TYPE,
          channel: channels[1],
          enabled: true,
          matchQuality: 1,
        },
      ]);
    });

    test("sorts joinable channels alongside native chatables", function (assert) {
      const user = { type: "user", enabled: true, matchQuality: 3 };
      const channel = {
        type: JOINABLE_CHANNEL_CHATABLE_TYPE,
        enabled: true,
        matchQuality: 1,
      };
      const group = { type: "group", enabled: true, matchQuality: 1 };

      assert.deepEqual(sortWorkspaceChatables([user, group, channel]), [
        channel,
        group,
        user,
      ]);
    });

    test("builds chat route models after joining", function (assert) {
      assert.deepEqual(
        chatRouteModels({ chat_channel_slug: "town-square", chat_channel_id: 12 }),
        ["town-square", 12]
      );
      assert.deepEqual(chatRouteModels({ chat_channel_id: 12 }), ["-", 12]);
    });
  }
);
