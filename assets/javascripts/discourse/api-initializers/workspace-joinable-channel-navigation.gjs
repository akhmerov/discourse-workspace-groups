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
    hashtagType: anchor.dataset?.type,
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
  if (chatCandidate(candidate)) {
    return candidate.target;
  }

  if (channel?.mode === "chat_only" && channel.chat_channel_id) {
    return `/chat/c/${channel.chat_channel?.slug || "-"}/${channel.chat_channel_id}`;
  }

  return candidate.target;
}

function navigateTo(target) {
  DiscourseURL.routeTo(target);
}

function chatCandidate(candidate) {
  return candidate?.target?.startsWith("/chat/c/");
}

export function hashtagCandidate(candidate) {
  return (
    candidate?.hashtagType === "channel" ||
    candidate?.hashtagType === "category"
  );
}

function currentPath() {
  return `${window.location.pathname}${window.location.search}${window.location.hash}`;
}

function nextFrame() {
  return new Promise((resolve) => requestAnimationFrame(resolve));
}

async function restorePreviousRoute(candidate, router) {
  if (!candidate.previousURL || currentPath() === candidate.previousURL) {
    return;
  }

  await new Promise((resolve) => {
    let settled = false;
    let timer;

    const finish = () => {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(timer);
      router.off("routeDidChange", finish);
      resolve();
    };

    timer = setTimeout(finish, 1500);
    router.on("routeDidChange", finish);
    window.history.back();
  });

  await nextFrame();
  await nextFrame();
}

function shouldResolveBeforeNativeRoute(candidate) {
  return (
    candidate &&
    currentPath().startsWith("/chat/") &&
    hashtagCandidate(candidate)
  );
}

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const siteSettings = api.container.lookup("service:site-settings");

  if (!currentUser || !siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  const router = api.container.lookup("service:router");
  const dialog = api.container.lookup("service:dialog");
  let pendingCandidate = null;
  let resolvingCandidate = false;

  async function resolveCandidate(
    candidate,
    { fallbackToTarget, restoreBeforePrompt } = {}
  ) {
    resolvingCandidate = true;

    let result;

    try {
      result = await ajax("/workspace-groups/joinable-channel.json", {
        data: { path: candidate.resolverPath },
      });
    } catch {
      if (fallbackToTarget) {
        navigateTo(candidate.target);
      }
      resolvingCandidate = false;
      return;
    }

    const channel = result?.channel;

    if (channel?.joined) {
      navigateTo(targetAfterJoin(candidate, channel));
      resolvingCandidate = false;
      return;
    }

    if (!channel?.can_join || !channel.workspace_id) {
      if (fallbackToTarget) {
        navigateTo(candidate.target);
      }
      resolvingCandidate = false;
      return;
    }

    if (restoreBeforePrompt) {
      await restorePreviousRoute(candidate, router);
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
  }

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
        previousURL: currentPath(),
      };

      if (shouldResolveBeforeNativeRoute(pendingCandidate)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        const candidate = pendingCandidate;
        pendingCandidate = null;
        setTimeout(() =>
          resolveCandidate(candidate, { fallbackToTarget: true })
        );
      }
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
    resolveCandidate(candidate, { restoreBeforePrompt: true });
  });
});
