import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { apiInitializer } from "discourse/lib/api";
import {
  openLinkInNewTab,
  shouldOpenInNewTab,
} from "discourse/lib/click-track";
import { iconHTML } from "discourse/lib/icon-library";
import WorkspaceChannelMembersModal from "discourse/plugins/discourse-workspace-groups/discourse/components/modal/workspace-channel-members";
import WorkspaceChannelSettingsModal from "discourse/plugins/discourse-workspace-groups/discourse/components/modal/workspace-channel-settings";

const CONTEXT_CLASS = "workspace-channel-context";
const CONTEXT_SELECTOR = `.${CONTEXT_CLASS}`;
const OPEN_CONTAINER_CLASS = `${CONTEXT_CLASS}-container--open`;

const workspaceChannelCache = new Map();
const BLOCK_TAGS = new Set([
  "ADDRESS",
  "ARTICLE",
  "ASIDE",
  "BLOCKQUOTE",
  "DETAILS",
  "DIV",
  "DL",
  "FIELDSET",
  "FIGCAPTION",
  "FIGURE",
  "FOOTER",
  "FORM",
  "H1",
  "H2",
  "H3",
  "H4",
  "H5",
  "H6",
  "HEADER",
  "HR",
  "LI",
  "MAIN",
  "NAV",
  "OL",
  "P",
  "PRE",
  "SECTION",
  "TABLE",
  "UL",
]);

function hasSingleSourceLine(raw) {
  return raw?.split(/\r?\n/).filter((line) => line.trim()).length === 1;
}

function isBlockElement(element) {
  return BLOCK_TAGS.has(element.tagName);
}

function isWorkspaceChannelChatable(chatable) {
  return !!(
    chatable?.workspace_kind === "channel" ||
    chatable?.workspace_channel_mode
  );
}

function workspaceCategoryId(channel) {
  const chatable = channel?.chatable;

  return (
    chatable?.workspace_parent_category?.id ||
    chatable?.workspace_parent_category_id ||
    chatable?.parent_category_id
  );
}

function channelCategoryId(channel) {
  return channel?.chatable?.id;
}

function isWorkspaceCategoryChatChannel(channel) {
  return !!(
    channel?.isCategoryChannel &&
    isWorkspaceChannelChatable(channel.chatable) &&
    workspaceCategoryId(channel) &&
    channelCategoryId(channel)
  );
}

function workspaceChannelKey(channel) {
  return `${workspaceCategoryId(channel)}:${channelCategoryId(channel)}`;
}

function firstDescriptionHtml(channel, workspaceChannel) {
  const cooked =
    workspaceChannel?.description_cooked || channel?.chatable?.description;
  if (!cooked) {
    return "";
  }

  const documentFragment = new DOMParser().parseFromString(cooked, "text/html");
  const bodyHtml = documentFragment.body.innerHTML.trim();
  const raw =
    workspaceChannel?.description_raw || channel?.chatable?.description_raw;

  if (hasSingleSourceLine(raw)) {
    return bodyHtml;
  }

  const firstBlock = [...documentFragment.body.children].find(
    (element) => element.textContent?.trim() || element.querySelector("a")
  );

  if (!firstBlock) {
    return "";
  }

  if (!isBlockElement(firstBlock)) {
    return bodyHtml;
  }

  return firstBlock.innerHTML.trim();
}

function categoryUrl(channel, workspaceChannel) {
  const mode =
    workspaceChannel?.mode || channel?.chatable?.workspace_channel_mode;
  if (mode !== "both") {
    return null;
  }

  return channel?.chatableUrl || channel?.chatable?.url || null;
}

function loadWorkspaceChannel(channel, rerender) {
  if (!isWorkspaceCategoryChatChannel(channel)) {
    return null;
  }

  const workspaceId = workspaceCategoryId(channel);
  const channelId = channelCategoryId(channel);
  const cacheKey = workspaceChannelKey(channel);
  let entry = workspaceChannelCache.get(cacheKey);

  if (!entry) {
    entry = { status: "pending", value: null };
    workspaceChannelCache.set(cacheKey, entry);

    entry.promise = fetch(`/workspace-groups/workspaces/${workspaceId}.json`, {
      headers: { "X-Requested-With": "XMLHttpRequest" },
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Workspace metadata returned HTTP ${response.status}`);
        }

        return response.json();
      })
      .then((result) => {
        entry.status = "fulfilled";
        entry.value = {
          workspace: result.workspace,
          channel:
            result.channels?.find((candidate) => candidate.id === channelId) ||
            null,
        };

        return entry.value;
      })
      .catch((error) => {
        entry.status = "rejected";
        entry.error = error;

        // Keep chat header rendering non-fatal; failed workspace metadata should
        // not break the normal chat header.
        // eslint-disable-next-line no-console
        console.warn("Failed to load workspace channel header data", error);
      })
      .finally(() => rerender?.());
  }

  return entry;
}

function workspaceData(channel, rerender) {
  const entry = loadWorkspaceChannel(channel, rerender);
  return entry?.status === "fulfilled" ? entry.value : null;
}

function buildIconButton(label, icon, className) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = className;
  button.title = label;
  button.ariaLabel = label;
  button.innerHTML = iconHTML(icon);

  return button;
}

function buildIconLink(href, label, icon, className) {
  if (!href) {
    return null;
  }

  const link = document.createElement("a");
  link.className = className;
  link.href = href;
  link.title = label;
  link.ariaLabel = label;
  link.innerHTML = iconHTML(icon);
  return link;
}

function updateActiveChatable(activeChannel, updatedChannel) {
  if (activeChannel?.chatable && updatedChannel.description_cooked) {
    activeChannel.chatable.description = updatedChannel.description_cooked;
  }

  if (activeChannel?.chatable && updatedChannel.mode) {
    activeChannel.chatable.workspace_channel_mode = updatedChannel.mode;
  }
}

async function loadWorkspaceModalData(data) {
  const result = await ajax(
    `/workspace-groups/workspaces/${data.workspaceId}.json`
  );
  const channel = result.channels?.find(
    (candidate) => candidate.id === data.channelId
  );

  return channel ? { workspace: result.workspace, channel } : null;
}

async function openWorkspaceChannelSettings(
  chat,
  modal,
  activeChannel,
  data,
  rerender = () => scheduleRender(chat, modal)
) {
  try {
    const modalData = await loadWorkspaceModalData(data);
    if (!modalData) {
      return;
    }

    modal.show(WorkspaceChannelSettingsModal, {
      model: {
        category: { id: data.workspaceId },
        workspace: modalData.workspace,
        channel: modalData.channel,
        onOpenMembers: () =>
          openWorkspaceChannelMembers(chat, modal, activeChannel, data, rerender),
        onUpdate: async (updatedChannel) => {
          Object.assign(modalData.channel, updatedChannel);
          updateActiveChatable(activeChannel, updatedChannel);
          workspaceChannelCache.clear();
          rerender();
        },
      },
    });
  } catch (error) {
    popupAjaxError(error);
  }
}

async function openWorkspaceChannelMembers(
  chat,
  modal,
  activeChannel,
  data,
  rerender = () => scheduleRender(chat, modal)
) {
  try {
    const modalData = await loadWorkspaceModalData(data);
    if (!modalData) {
      return;
    }

    modal.show(WorkspaceChannelMembersModal, {
      model: {
        category: { id: data.workspaceId },
        workspace: modalData.workspace,
        channel: modalData.channel,
        onUpdate: async (updatedChannel) => {
          Object.assign(modalData.channel, updatedChannel);
          updateActiveChatable(activeChannel, updatedChannel);
          workspaceChannelCache.clear();
          rerender();
        },
      },
    });
  } catch (error) {
    popupAjaxError(error);
  }
}

function buildDescription(descriptionHtml) {
  if (!descriptionHtml) {
    return null;
  }

  const description = document.createElement("span");
  description.className = `${CONTEXT_CLASS}__description`;
  description.innerHTML = descriptionHtml;
  description.addEventListener("click", openExternalLinkWithUserPreference);
  return description;
}

function openExternalLinkWithUserPreference(event) {
  const link = event.target.closest?.("a[href]");
  if (!link || !event.currentTarget.contains(link)) {
    return;
  }

  if (shouldOpenInNewTab(link.href)) {
    openLinkInNewTab(event, link);
  }
}

function buildMembersButton(chat, modal, channel, data) {
  if (!data.canViewMembers) {
    return null;
  }

  const button = buildIconButton(
    "Channel members",
    "user",
    `${CONTEXT_CLASS}__link ${CONTEXT_CLASS}__icon-action ${CONTEXT_CLASS}__members`
  );
  button.addEventListener("click", () =>
    openWorkspaceChannelMembers(chat, modal, channel, data)
  );

  return button;
}

function buildSettingsButton(chat, modal, channel, data) {
  if (!data.canSeeSettings) {
    return null;
  }

  const button = buildIconButton(
    "Channel settings",
    "wrench",
    `${CONTEXT_CLASS}__link ${CONTEXT_CLASS}__icon-action ${CONTEXT_CLASS}__settings`
  );
  button.addEventListener("click", () =>
    openWorkspaceChannelSettings(chat, modal, channel, data)
  );

  return button;
}

function contextData(channel, rerender) {
  const data = workspaceData(channel, rerender);
  const workspaceChannel = data?.channel;
  const descriptionHtml = firstDescriptionHtml(channel, workspaceChannel);
  const categoryHref = categoryUrl(channel, workspaceChannel);
  const workspaceId = workspaceCategoryId(channel);
  const channelId = channelCategoryId(channel);
  const canViewMembers = !!workspaceChannel?.can_view_members;
  const canSeeSettings = !!(
    workspaceChannel &&
    (data?.workspace?.can_manage ||
      workspaceChannel.can_archive ||
      workspaceChannel.can_unarchive)
  );

  return {
    workspaceId,
    channelId,
    descriptionHtml,
    categoryHref,
    canViewMembers,
    canSeeSettings,
    signature: JSON.stringify({
      channelId: channel?.id,
      descriptionHtml,
      categoryHref,
      canViewMembers,
      canSeeSettings,
    }),
  };
}

function buildContext(chat, modal, channel, data) {
  const description = buildDescription(data.descriptionHtml);
  const category = buildIconLink(
    data.categoryHref,
    "Forum category",
    "list",
    `${CONTEXT_CLASS}__link ${CONTEXT_CLASS}__icon-action ${CONTEXT_CLASS}__category`
  );
  const members = buildMembersButton(chat, modal, channel, data);
  const settings = buildSettingsButton(chat, modal, channel, data);
  const contentItems = [description, category, members, settings].filter(Boolean);

  if (contentItems.length === 0) {
    return null;
  }

  const context = document.createElement("div");
  context.className = CONTEXT_CLASS;
  context.dataset.channelId = String(channel.id);
  context.dataset.signature = data.signature;

  const toggle = document.createElement("button");
  toggle.type = "button";
  toggle.className = `${CONTEXT_CLASS}__toggle`;
  toggle.title = "Show channel details";
  toggle.ariaLabel = "Show channel details";
  toggle.ariaExpanded = "false";
  toggle.innerHTML = iconHTML("info");
  toggle.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();

    const rect = toggle.getBoundingClientRect();
    context.style.setProperty(
      "--workspace-channel-context-top",
      `${rect.bottom + 8}px`
    );
    const isOpen = context.classList.toggle(`${CONTEXT_CLASS}--open`);
    context
      .closest(".c-navbar-container")
      ?.classList.toggle(OPEN_CONTAINER_CLASS, isOpen);
    toggle.ariaExpanded = String(isOpen);
  });
  context.append(toggle);

  const content = document.createElement("div");
  content.className = `${CONTEXT_CLASS}__content`;
  contentItems.forEach((item) => content.append(item));
  context.append(content);

  return context;
}

function renderChatContext(chat, modal) {
  const navbar = document.querySelector(".c-navbar");
  if (!navbar) {
    return;
  }

  const channel = chat.activeChannel;
  if (!isWorkspaceCategoryChatChannel(channel)) {
    const existingContext = navbar.querySelector(CONTEXT_SELECTOR);
    existingContext
      ?.closest(".c-navbar-container")
      ?.classList.remove(OPEN_CONTAINER_CLASS);
    existingContext?.remove();
    return;
  }

  const title = navbar.querySelector(".c-navbar__channel-title");
  if (!title) {
    return;
  }

  const data = contextData(channel, () => scheduleRender(chat, modal));
  const existingContext = navbar.querySelector(CONTEXT_SELECTOR);
  if (
    existingContext?.dataset.channelId === String(channel.id) &&
    existingContext?.dataset.signature === data.signature
  ) {
    return;
  }

  existingContext
    ?.closest(".c-navbar-container")
    ?.classList.remove(OPEN_CONTAINER_CLASS);
  existingContext?.remove();

  const context = buildContext(chat, modal, channel, data);
  if (!context) {
    return;
  }

  title.after(context);
}

function scheduleRender(chat, modal) {
  requestAnimationFrame(() => {
    renderChatContext(chat, modal);
  });
}

export default apiInitializer((api) => {
  const chat = api.container.lookup("service:chat");
  const modal = api.container.lookup("service:modal");
  const router = api.container.lookup("service:router");
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings?.chat_enabled || !chat || !modal || !router) {
    return;
  }

  router.on("routeDidChange", () => scheduleRender(chat, modal));

  const observer = new MutationObserver(() => scheduleRender(chat, modal));
  observer.observe(document.body, { childList: true, subtree: true });

  scheduleRender(chat, modal);
});
