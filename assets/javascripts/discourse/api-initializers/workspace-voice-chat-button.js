import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";
import { iconHTML } from "discourse/lib/icon-library";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  const container = api.container;
  const settings = container.lookup("service:site-settings");
  if (!settings.discourse_workspace_groups_enabled || !settings.voice_enabled) {
    return;
  }
  const chat = container.lookup("service:chat");
  const router = container.lookup("service:router");
  const voice = container.lookup("service:workspace-voice");
  let dmId;
  let dmCanCall = false;
  async function refreshDm() {
    const id = chat.activeChannel?.isDirectMessageChannel
      ? chat.activeChannel.id
      : null;
    if (id !== dmId) {
      dmId = id;
      dmCanCall = false;
    }
    if (id) {
      try {
        const result = await ajax(`/workspace-groups/voice/dms/${id}.json`);
        if (dmId === id) {
          dmCanCall = result.can_call;
        }
      } catch {
        dmCanCall = false;
      }
      scheduleRender();
    }
  }
  function render() {
    const navbar = document.querySelector(".c-navbar");
    if (!navbar) {
      return;
    }
    const channel = chat.activeChannel;
    if (channel?.isDirectMessageChannel && channel.id !== dmId) {
      refreshDm();
    }
    let path;
    if (channel?.isDirectMessageChannel && channel.id === dmId && dmCanCall) {
      path = `/workspace-voice/dms/${channel.id}`;
    } else if (
      channel?.isCategoryChannel &&
      voice.channels.some((item) => item.category_id === channel.chatable?.id)
    ) {
      path = `/workspace-voice/channels/${channel.chatable.id}`;
    }
    let link = navbar.querySelector(".workspace-voice-chat-button");
    if (!path) {
      link?.remove();
      return;
    }
    if (link?.getAttribute("href") === path) {
      return;
    }
    link?.remove();
    link = document.createElement("a");
    link.className = "btn btn-transparent workspace-voice-chat-button";
    link.href = path;
    link.title = i18n("discourse_workspace_groups.voice.call");
    link.setAttribute("aria-label", link.title);
    link.innerHTML = iconHTML("microphone");
    link.addEventListener("click", (event) => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) {
        return;
      }
      event.preventDefault();
      router.transitionTo(path);
    });
    (navbar.querySelector(".c-navbar__actions") || navbar).prepend(link);
  }
  function scheduleRender() {
    requestAnimationFrame(render);
  }
  api.onPageChange(() => {
    refreshDm();
    scheduleRender();
  });
  const timer = setInterval(refreshDm, 10000);
  window.addEventListener("pagehide", () => clearInterval(timer), {
    once: true,
  });
  const observer = new MutationObserver(scheduleRender);
  observer.observe(document.body, { childList: true, subtree: true });
  scheduleRender();
});
