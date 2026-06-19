import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { apiInitializer } from "discourse/lib/api";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";

export function internalWorkspaceCandidatePath(anchor) {
  if (!anchor?.href || anchor.download) {
    return null;
  }

  if (anchor.target && anchor.target !== "_self") {
    return null;
  }

  const url = new URL(anchor.href, window.location.origin);

  if (url.origin !== window.location.origin) {
    return null;
  }

  if (!url.pathname.startsWith("/c/") && !url.pathname.startsWith("/t/")) {
    return null;
  }

  return {
    target: `${url.pathname}${url.search}${url.hash}`,
    resolverPath: url.pathname,
  };
}

function modifiedClick(event) {
  return (
    event.button !== 0 ||
    event.metaKey ||
    event.ctrlKey ||
    event.shiftKey ||
    event.altKey
  );
}

async function joinChannel(channel) {
  return await ajax(
    `/workspace-groups/workspaces/${channel.workspace_id}/channels/${channel.id}/membership`,
    { type: "POST" }
  );
}

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const siteSettings = api.container.lookup("service:site-settings");

  if (!currentUser || !siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  const dialog = api.container.lookup("service:dialog");

  document.addEventListener(
    "click",
    async (event) => {
      if (event.defaultPrevented || modifiedClick(event)) {
        return;
      }

      const candidate = internalWorkspaceCandidatePath(
        event.target?.closest?.("a[href]")
      );

      if (!candidate) {
        return;
      }

      event.preventDefault();
      event.stopImmediatePropagation();

      let result;

      try {
        result = await ajax("/workspace-groups/joinable-channel.json", {
          data: { path: candidate.resolverPath },
        });
      } catch {
        DiscourseURL.routeTo(candidate.target);
        return;
      }

      const channel = result?.channel;

      if (!channel?.can_join || !channel.workspace_id) {
        DiscourseURL.routeTo(candidate.target);
        return;
      }

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
        await joinChannel(channel);
        DiscourseURL.routeTo(candidate.target);
      } catch (error) {
        popupAjaxError(error);
      }
    },
    true
  );
});
