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
  if (chatCandidate(candidate)) {
    return candidate.target;
  }

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

function routeToNativeTarget(target) {
  DiscourseURL.routeTo(target);
}

function confirmJoinChannel(channel) {
  return new Promise((resolve) => {
    const container = document.createElement("div");
    container.className = "dialog-container workspace-join-channel-dialog";
    container.innerHTML = `
      <div class="dialog-overlay"></div>
      <div class="dialog-content" role="document">
        <div class="dialog-body">
          <p></p>
        </div>
        <div class="dialog-footer">
          <button type="button" class="btn btn-primary"></button>
          <button type="button" class="btn btn-default"></button>
        </div>
      </div>
    `;

    const message = container.querySelector(".dialog-body p");
    const confirmButton = container.querySelector(".btn-primary");
    const cancelButton = container.querySelector(".btn-default");

    message.textContent = i18n(
      "discourse_workspace_groups.join_channel_message",
      {
        channel_name: channel.name,
      }
    );
    confirmButton.textContent = i18n(
      "discourse_workspace_groups.join_channel_confirm"
    );
    cancelButton.textContent = i18n("cancel");

    const cleanup = (result) => {
      document.removeEventListener("keydown", handleKeydown);
      container.remove();
      resolve(result);
    };

    const handleKeydown = (event) => {
      if (event.key === "Escape") {
        cleanup(false);
      }
    };

    confirmButton.addEventListener("click", () => cleanup(true), { once: true });
    cancelButton.addEventListener("click", () => cleanup(false), { once: true });
    container
      .querySelector(".dialog-overlay")
      .addEventListener("click", () => cleanup(false), { once: true });
    document.addEventListener("keydown", handleKeydown);
    document.body.append(container);
    confirmButton.focus();
  });
}

function chatCandidate(candidate) {
  return candidate?.target?.startsWith("/chat/c/");
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
    candidate && (chatCandidate(candidate) || currentPath().startsWith("/chat/"))
  );
}

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const siteSettings = api.container.lookup("service:site-settings");

  if (!currentUser || !siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  const router = api.container.lookup("service:router");
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
        routeToNativeTarget(candidate.target);
      }
      resolvingCandidate = false;
      return;
    }

    const channel = result?.channel;

    if (channel?.joined) {
      const target = targetAfterJoin(candidate, channel);
      if (target === candidate.target) {
        routeToNativeTarget(target);
      } else {
        navigateTo(target);
      }
      resolvingCandidate = false;
      return;
    }

    if (!channel?.can_join || !channel.workspace_id) {
      if (fallbackToTarget) {
        routeToNativeTarget(candidate.target);
      }
      resolvingCandidate = false;
      return;
    }

    if (restoreBeforePrompt) {
      await restorePreviousRoute(candidate, router);
    }

    const confirmed = await confirmJoinChannel(channel);

    if (!confirmed) {
      navigateTo(candidate.previousURL);
      resolvingCandidate = false;
      return;
    }

    try {
      const result = await joinChannel(channel);
      const target = targetAfterJoin(candidate, result?.channel || channel);
      if (target === candidate.target) {
        routeToNativeTarget(target);
      } else {
        navigateTo(target);
      }
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
