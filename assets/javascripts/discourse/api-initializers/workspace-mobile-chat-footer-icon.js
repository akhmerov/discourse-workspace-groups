import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";
import {
  focusedWorkspaceCategory,
  rememberedOrDefaultWorkspaceCategory,
  WORKSPACE_FOCUS_CHANGED_EVENT,
  WORKSPACE_FOCUS_KEY,
} from "../lib/workspace-team-sidebar-state";

const FOOTER_CHANNELS_SELECTOR = "#c-footer-channels";
const FOOTER_SEARCH_SELECTOR = "#c-footer-search";
const NATIVE_CHANNELS_ICON = "comments";
const WORKSPACE_CHANNELS_ICON = "list";
const NATIVE_LABEL = "chat.channel_list.aria_label";
const WORKSPACE_LABEL = "discourse_workspace_groups.open_workspace_channels";

function services(container, siteSettings, router) {
  return {
    chat: container.lookup("service:chat"),
    chatChannelsManager: container.lookup("service:chat-channels-manager"),
    currentUser: container.lookup("service:current-user"),
    router,
    site: container.lookup("service:site"),
    siteSettings,
    topicCategory: null,
  };
}

function inMobileChat(router, site) {
  return !!(
    site?.mobileView &&
    (router.currentRouteName?.startsWith("chat.") ||
      router.currentURL?.startsWith("/chat"))
  );
}

function setChannelFooterState({ iconName, workspaceAvailable }) {
  const button = document.querySelector(FOOTER_CHANNELS_SELECTOR);
  const icon = button?.querySelector(".d-icon");
  const use = icon?.querySelector("use");

  if (!button || !icon || !use) {
    return;
  }

  icon.classList.remove(
    `d-icon-${NATIVE_CHANNELS_ICON}`,
    `d-icon-${WORKSPACE_CHANNELS_ICON}`
  );
  icon.classList.add(`d-icon-${iconName}`);
  use.setAttribute("href", `#${iconName}`);
  use.setAttribute("xlink:href", `#${iconName}`);
  button.classList.toggle(
    "workspace-groups-chat-footer-workspace",
    workspaceAvailable
  );

  const label = i18n(workspaceAvailable ? WORKSPACE_LABEL : NATIVE_LABEL);
  button.setAttribute("aria-label", label);
  button.setAttribute("title", label);
}

export default apiInitializer((api) => {
  const container = api.container;
  const siteSettings = container.lookup("service:site-settings");

  if (!siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  const router = container.lookup("service:router");
  const site = container.lookup("service:site");

  function currentServices() {
    return services(container, siteSettings, router);
  }

  function workspaceCandidate() {
    const serviceBag = currentServices();

    return (
      focusedWorkspaceCategory(serviceBag) ||
      rememberedOrDefaultWorkspaceCategory(serviceBag)
    );
  }

  function workspaceFooterAvailable() {
    return !!(inMobileChat(router, site) && workspaceCandidate());
  }

  function updateFooterIcon() {
    const workspaceAvailable = workspaceFooterAvailable();

    setChannelFooterState({
      iconName: workspaceAvailable ? WORKSPACE_CHANNELS_ICON : NATIVE_CHANNELS_ICON,
      workspaceAvailable,
    });
  }

  function scheduleFooterIconUpdate() {
    requestAnimationFrame(updateFooterIcon);
    requestAnimationFrame(() => requestAnimationFrame(updateFooterIcon));
  }

  api.onPageChange(scheduleFooterIconUpdate);
  window.addEventListener(
    WORKSPACE_FOCUS_CHANGED_EVENT,
    scheduleFooterIconUpdate
  );
  document.addEventListener(
    "click",
    (event) => {
      const button = event.target.closest?.(FOOTER_CHANNELS_SELECTOR);

      if (!button || !inMobileChat(router, site)) {
        return;
      }

      const workspace = workspaceCandidate();

      if (!workspace?.id) {
        return;
      }

      try {
        sessionStorage.setItem(WORKSPACE_FOCUS_KEY, String(workspace.id));
      } catch {
        // Ignore storage failures; the current event still lets mounted panels update.
      }

      window.dispatchEvent(
        new CustomEvent(WORKSPACE_FOCUS_CHANGED_EVENT, {
          detail: { workspaceId: String(workspace.id) },
        })
      );

      if (router.currentRouteName === "chat.channels") {
        event.preventDefault();
        event.stopPropagation();
      }

      scheduleFooterIconUpdate();
    },
    true
  );
  document.addEventListener(
    "click",
    (event) => {
      const button = event.target.closest?.(FOOTER_SEARCH_SELECTOR);

      if (!button || !workspaceFooterAvailable()) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      router.transitionTo("chat.new-message");
    },
    true
  );
  scheduleFooterIconUpdate();
});
