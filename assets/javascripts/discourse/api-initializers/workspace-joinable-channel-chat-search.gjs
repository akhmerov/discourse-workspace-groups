import { getOwner } from "@ember/owner";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { apiInitializer } from "discourse/lib/api";
import {
  JOINABLE_CHANNEL_CHATABLE_TYPE,
  chatRouteModels,
  joinableChannelItems,
  sortWorkspaceChatables,
} from "../lib/workspace-joinable-channel-chat-search";
import WorkspaceJoinableChannelChatable from "../components/workspace-joinable-channel-chatable";
import { i18n } from "discourse-i18n";

const MAX_RESULTS = 10;

async function joinChannel(channel) {
  return await ajax(
    `/workspace-groups/workspaces/${channel.workspace_id}/channels/${channel.id}/membership`,
    { type: "POST" }
  );
}

function hasRegistration(container, name) {
  return container.hasRegistration?.(name) || container.factoryFor?.(name);
}

async function fetchJoinableChannels(term, chatables) {
  if (!term?.trim()) {
    return [];
  }

  const result = await ajax("/workspace-groups/joinable-channels.json", {
    data: { term },
  });

  return joinableChannelItems(result.channels || [], chatables);
}

async function selectJoinableChannel(search, item) {
  const owner = getOwner(search);
  const dialog = owner.lookup("service:dialog");
  const router = owner.lookup("service:router");
  const channel = item.channel;

  const confirmed = await dialog.confirm({
    message: i18n("discourse_workspace_groups.join_channel_message", {
      channel_name: channel.name,
    }),
    confirmButtonLabel: "discourse_workspace_groups.join_channel_confirm",
    cancelButtonLabel: "cancel",
  });

  if (!confirmed) {
    return;
  }

  try {
    const result = await joinChannel(channel);
    const joinedChannel = result?.channel || channel;

    search.args.close?.();
    router.transitionTo("chat.channel", ...chatRouteModels(joinedChannel));
  } catch (error) {
    popupAjaxError(error);
  }
}

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const siteSettings = api.container.lookup("service:site-settings");

  if (
    !currentUser ||
    !siteSettings?.discourse_workspace_groups_enabled ||
    !hasRegistration(api.container, "service:chat") ||
    !hasRegistration(api.container, "component:chat/message-creator/search") ||
    !hasRegistration(api.container, "component:chat/message-creator/list")
  ) {
    return;
  }

  api.modifyClass(
    "component:chat/message-creator/list",
    (Superclass) =>
      class extends Superclass {
        componentForItem(type) {
          if (type === JOINABLE_CHANNEL_CHATABLE_TYPE) {
            return WorkspaceJoinableChannelChatable;
          }

          return super.componentForItem(type);
        }
      }
  );

  api.modifyClass(
    "component:chat/message-creator/search",
    (Superclass) =>
      class extends Superclass {
        @action
        async fetch() {
          await super.fetch(...arguments);

          try {
            const joinableChannels = await fetchJoinableChannels(
              this.term,
              this.chatables
            );

            this.chatables = sortWorkspaceChatables([
              ...this.chatables,
              ...joinableChannels,
            ]).slice(0, MAX_RESULTS);
            this.highlightedChatable = this.items[0];
          } catch (error) {
            popupAjaxError(error);
          }
        }

        @action
        async selectChatable(item) {
          if (item.type === JOINABLE_CHANNEL_CHATABLE_TYPE) {
            await selectJoinableChannel(this, item);
            return;
          }

          return await super.selectChatable(item);
        }
      }
  );
});
