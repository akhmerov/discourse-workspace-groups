export const JOINABLE_CHANNEL_CHATABLE_TYPE = "workspace-joinable-channel";

const MATCH_QUALITY_PARTIAL = 3;
const TYPE_PRIORITY = {
  user: 0,
  channel: 2,
  group: 3,
  [JOINABLE_CHANNEL_CHATABLE_TYPE]: 2,
};

export function chatRouteModels(channel) {
  return [channel.chat_channel_slug || "-", channel.chat_channel_id];
}

export function nativeChannelIds(chatables) {
  return new Set(
    chatables
      .filter((chatable) => chatable.type === "channel")
      .map((chatable) => chatable.model?.id)
      .filter(Boolean)
  );
}

export function joinableChannelItem(channel) {
  return {
    identifier: `${JOINABLE_CHANNEL_CHATABLE_TYPE}-${channel.id}`,
    type: JOINABLE_CHANNEL_CHATABLE_TYPE,
    channel,
    enabled: true,
    matchQuality: channel.match_quality,
  };
}

export function sortWorkspaceChatables(chatables) {
  return chatables.sort((a, b) => {
    const matchA = a.matchQuality ?? MATCH_QUALITY_PARTIAL;
    const matchB = b.matchQuality ?? MATCH_QUALITY_PARTIAL;

    if (matchA !== matchB) {
      return matchA - matchB;
    }

    const typeA = TYPE_PRIORITY[a.type] ?? TYPE_PRIORITY.channel;
    const typeB = TYPE_PRIORITY[b.type] ?? TYPE_PRIORITY.channel;

    if (typeA !== typeB) {
      return typeA - typeB;
    }

    if (a.enabled !== b.enabled) {
      return a.enabled ? -1 : 1;
    }

    return 0;
  });
}

export function joinableChannelItems(channels, chatables) {
  const channelIds = nativeChannelIds(chatables);

  return channels
    .filter(
      (channel) => channel.chat_channel_id && !channelIds.has(channel.chat_channel_id)
    )
    .map(joinableChannelItem);
}
