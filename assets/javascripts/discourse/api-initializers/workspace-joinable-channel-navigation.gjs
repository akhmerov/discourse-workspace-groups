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

  if (
    !url.pathname.startsWith("/c/") &&
    !url.pathname.startsWith("/t/") &&
    !url.pathname.startsWith("/chat/c/")
  ) {
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

function failedRoute(transition, router) {
  const routeName = transition?.to?.name;

  return (
    routeName === "exception" ||
    routeName === "exception-unknown" ||
    routeName === "unknown" ||
    router.currentURL === "/404"
  );
}

async function joinChannel(channel) {
  return await ajax(
    `/workspace-groups/workspaces/${channel.workspace_id}/channels/${channel.id}/membership`,
    { type: "POST" }
  );
}

export function targetAfterJoin(candidate, channel) {
  if (channel?.mode === "chat_only" && channel.chat_channel_id) {
    return `/chat/c/${channel.chat_channel?.slug || "-"}/${channel.chat_channel_id}`;
  }

  return candidate.target;
}

function navigateTo(target) {
  if (target?.startsWith("/chat/c/")) {
    window.location.assign(target);
  } else {
    DiscourseURL.routeTo(target);
  }
}

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const siteSettings = api.container.lookup("service:site-settings");

  if (!currentUser || !siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  const dialog = api.container.lookup("service:dialog");
  const router = api.container.lookup("service:router");
  let pendingCandidate = null;
  let resolvingCandidate = false;

  document.addEventListener(
    "click",
    (event) => {
      if (modifiedClick(event)) {
        pendingCandidate = null;
        return;
      }

      const candidate = internalWorkspaceCandidatePath(
        event.target?.closest?.("a[href]")
      );

      pendingCandidate = candidate && {
        ...candidate,
        previousURL: `${window.location.pathname}${window.location.search}${
          window.location.hash
        }`,
      };
    },
    true
  );

  router.on("routeDidChange", async (transition) => {
    if (!pendingCandidate || resolvingCandidate) {
      return;
    }

    if (!failedRoute(transition, router)) {
      pendingCandidate = null;
      return;
    }

    const candidate = pendingCandidate;
    pendingCandidate = null;
    resolvingCandidate = true;

    let result;

    try {
      result = await ajax("/workspace-groups/joinable-channel.json", {
        data: { path: candidate.resolverPath },
      });
    } catch {
      resolvingCandidate = false;
      return;
    }

    const channel = result?.channel;

    if (channel?.joined) {
      const target = targetAfterJoin(candidate, channel);
      if (target !== candidate.target) {
        navigateTo(target);
      }
      resolvingCandidate = false;
      return;
    }

    if (!channel?.can_join || !channel.workspace_id) {
      resolvingCandidate = false;
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
      navigateTo(candidate.previousURL);
      resolvingCandidate = false;
      return;
    }

    try {
      const result = await joinChannel(channel);
      navigateTo(targetAfterJoin(candidate, result?.channel || channel));
    } catch (error) {
      popupAjaxError(error);
    } finally {
      resolvingCandidate = false;
    }
  });
});
