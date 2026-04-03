import Component from "@glimmer/component";
import { getOwner } from "@ember/owner";
import { next } from "@ember/runloop";
import { htmlSafe } from "@ember/template";
import { apiInitializer } from "discourse/lib/api";
import { canDisplayCategory } from "discourse/lib/sidebar/helpers";
import CategorySectionLink from "discourse/lib/sidebar/user/categories-section/category-section-link";
import DiscourseURL from "discourse/lib/url";
import Category from "discourse/models/category";
import SidebarAnonymousCategoriesSection from "discourse/components/sidebar/anonymous/categories-section";
import SidebarUserCategoriesSection from "discourse/components/sidebar/user/categories-section";
import icon from "discourse/helpers/d-icon";

const SCOPED_SIDEBAR_CLASS = "workspace-groups-scoped-sidebar";
const SCOPED_SIDEBAR_CHAT_MODE_CLASS =
  "workspace-groups-scoped-sidebar--chat";
const SIDEBAR_SECTION_NAME = "workspace-team";
const CATEGORY_CURRENT_WHEN =
  "discovery.unreadCategory discovery.hotCategory discovery.topCategory discovery.newCategory discovery.latestCategory discovery.category discovery.categoryNone discovery.categoryAll";
const CHAT_CURRENT_WHEN =
  "chat.channel chat.channel.thread chat.channel.threads chat.channel.pins chat.channel.info.settings chat.channel.info.members chat.channel.near-message chat.channel.near-message-with-thread";

export function workspaceScopedCategory(category) {
  if (!category) {
    return null;
  }

  if (
    category.workspace_enabled ||
    category.workspace_kind === "workspace" ||
    category.workspace_kind === "channel"
  ) {
    return category;
  }

  return null;
}

function ownerFor(instance) {
  return instance?.lookup ? instance : getOwner(instance);
}

function siteSettingsFor(instance) {
  return (
    instance.siteSettings ?? ownerFor(instance)?.lookup("service:site-settings")
  );
}

function currentUserFor(instance) {
  return (
    instance.currentUser ?? ownerFor(instance)?.lookup("service:current-user")
  );
}

function routerFor(instance) {
  return instance.router ?? ownerFor(instance)?.lookup("service:router");
}

function chatServiceFor(instance) {
  return instance.chat ?? ownerFor(instance)?.lookup("service:chat");
}

function siteFor(instance) {
  return instance.site ?? ownerFor(instance)?.lookup("service:site");
}

function visibleChildren(category, siteSettings, site) {
  if (!category || !site?.categoriesList?.length) {
    return [];
  }

  return site.categoriesList.filter(
    (candidate) =>
      candidate.parent_category_id === category.id &&
      canDisplayCategory(candidate.id, siteSettings)
  );
}

function currentScopedCategory(instance) {
  const router = routerFor(instance);
  const routeCategory = router.currentRoute?.attributes?.category;

  if (routeCategory) {
    return workspaceScopedCategory(routeCategory);
  }

  if (router?.currentRouteName?.startsWith("topic.")) {
    const topicCategory = ownerFor(instance)?.lookup("controller:topic")?.model
      ?.category;

    if (topicCategory) {
      return workspaceScopedCategory(topicCategory);
    }
  }

  const chat = chatServiceFor(instance);
  const activeChannel = chat?.activeChannel;

  if (!activeChannel?.isCategoryChannel || !activeChannel.chatableId) {
    return null;
  }

  return workspaceScopedCategory(Category.findById(activeChannel.chatableId));
}

export function sidebarScopedCategories(instance) {
  const currentCategory = currentScopedCategory(instance);
  const site = siteFor(instance);

  if (!currentCategory) {
    return null;
  }

  const directChildren = visibleChildren(
    currentCategory,
    siteSettingsFor(instance),
    site
  );

  if (directChildren.length > 0) {
    return [currentCategory, ...directChildren];
  }

  if (currentCategory.parent_category_id) {
    const parentCategory = Category.findById(currentCategory.parent_category_id);
    const siblingCategories = visibleChildren(
      parentCategory,
      siteSettingsFor(instance),
      site
    );

    if (siblingCategories.length > 0) {
      return [parentCategory, ...siblingCategories];
    }
  }

  return [];
}

function userSelectedScopedCategories(instance, scopedCategories) {
  const selectedIds = currentUserFor(instance)?.sidebarCategoryIds;

  if (!selectedIds?.length || !scopedCategories.length) {
    return null;
  }

  const [topLevelCategory, ...subcategories] = scopedCategories;
  const selectedScopedCategories = subcategories.filter((category) =>
    selectedIds.includes(category.id)
  );

  if (
    selectedScopedCategories.length > 0 &&
    selectedScopedCategories.length < subcategories.length
  ) {
    return [topLevelCategory, ...selectedScopedCategories];
  }

  return null;
}

function scopedCategoryIds(instance) {
  const scopedCategories = sidebarScopedCategories(instance);

  if (!scopedCategories) {
    return null;
  }

  return new Set(scopedCategories.slice(1).map((category) => category.id));
}

function pairedCategoryChannelFor(category, chatChannelsManager) {
  return chatChannelsManager?.channels?.find(
    (channel) =>
      channel.isCategoryChannel &&
      channel.chatableId === category.id &&
      channel.currentUserMembership?.following
  );
}

function sidebarChannelCategories(instance) {
  const scopedCategories = sidebarScopedCategories(instance);
  const chatChannelsManager =
    instance.chatChannelsManager ??
    ownerFor(instance)?.lookup("service:chat-channels-manager");

  if (!scopedCategories?.length) {
    return null;
  }

  const channelCategories = (
    userSelectedScopedCategories(instance, scopedCategories) ?? scopedCategories
  ).slice(1);

  return channelCategories.filter((category) =>
    pairedCategoryChannelFor(category, chatChannelsManager)
  );
}

function sidebarWorkspaceCategory(instance) {
  return sidebarScopedCategories(instance)?.[0] ?? null;
}

function workspaceOverviewPath(category) {
  if (!category) {
    return null;
  }

  return `${category.path}/overview`;
}

function memberWorkspaceCategories(instance) {
  const site = siteFor(instance);
  const siteSettings = siteSettingsFor(instance);

  if (!site?.categoriesList?.length) {
    return [];
  }

  return site.categoriesList.filter(
    (category) =>
      !category.parent_category_id &&
      category.workspace_kind === "workspace" &&
      canDisplayCategory(category.id, siteSettings)
  );
}

function currentScopedMode(instance) {
  const router = routerFor(instance);
  const chat = chatServiceFor(instance);

  if (
    router?.currentRouteName?.startsWith("chat.") &&
    chat?.activeChannel?.isCategoryChannel
  ) {
    return "chat";
  }

  return currentScopedCategory(instance) ? "category" : null;
}

function updateScopedSidebarClasses(instance) {
  const body = document.body;
  const categories = sidebarChannelCategories(instance);
  const mode = currentScopedMode(instance);
  const shouldEnable = !!categories?.length;

  body.classList.toggle(SCOPED_SIDEBAR_CLASS, shouldEnable);
  body.classList.toggle(
    SCOPED_SIDEBAR_CHAT_MODE_CLASS,
    shouldEnable && mode === "chat"
  );
}

function setInlineStyle(element, property, value) {
  if (!element) {
    return;
  }

  element.style[property] = value ?? "";
}

function syncScopedSidebarDom(instance) {
  const scoped = document.body.classList.contains(SCOPED_SIDEBAR_CLASS);
  const selectors = {
    categories: '#d-sidebar .sidebar-section[data-section-name="categories"]',
    merged: `#d-sidebar .sidebar-section[data-section-name="${SIDEBAR_SECTION_NAME}"]`,
    chatChannels:
      '#d-sidebar .sidebar-section[data-section-name="chat-channels"]',
  };
  const categoriesSection = document.querySelector(selectors.categories);
  const mergedSection = document.querySelector(selectors.merged);
  const chatChannelsSection = document.querySelector(selectors.chatChannels);
  const header = mergedSection?.querySelector(".sidebar-section-header");
  const headerText = mergedSection?.querySelector(
    ".sidebar-section-header-text"
  );
  const workspaceCategory = sidebarWorkspaceCategory(instance);
  const overviewPath = workspaceOverviewPath(workspaceCategory);

  setInlineStyle(mergedSection, "order", "5");
  setInlineStyle(categoriesSection, "order", "10");
  setInlineStyle(chatChannelsSection, "order", "11");
  setInlineStyle(categoriesSection, "display", scoped ? "none" : "");
  setInlineStyle(chatChannelsSection, "display", scoped ? "none" : "");
  setInlineStyle(header, "cursor", "");
  setInlineStyle(headerText, "cursor", scoped && overviewPath ? "pointer" : "");

  document
    .querySelectorAll(
      '#d-sidebar .sidebar-section[data-section-name="tags"], #d-sidebar .sidebar-section[data-section-name="chat-search"], #d-sidebar .sidebar-section[data-section-name="chat-starred-channels"], #d-sidebar .sidebar-section[data-section-name="chat-dms"]'
    )
    .forEach((section) => setInlineStyle(section, "order", scoped ? "20" : ""));

  if (headerText && scoped && overviewPath) {
    headerText.dataset.workspaceGroupPath = overviewPath;
    headerText.title = `Open ${workspaceCategory.displayName} overview`;
  } else if (headerText) {
    delete headerText.dataset.workspaceGroupPath;
    headerText.removeAttribute("title");
  }

  document
    .querySelectorAll(
      `#d-sidebar .sidebar-section[data-section-name="${SIDEBAR_SECTION_NAME}"] button[data-workspace-group-path]`
    )
    .forEach((button) => {
      button.dataset.workspaceGroupsBound = "1";
    });
}

function ensureScopedSidebarClickHandler() {
  if (document.body.dataset.workspaceGroupsClickHandlerBound === "1") {
    return;
  }

  document.body.dataset.workspaceGroupsClickHandlerBound = "1";
  const handleNavigation = (element, event) => {
    const path = element?.dataset?.workspaceGroupPath;
    const mode = element?.dataset?.workspaceGroupMode;

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation?.();

    if (!path) {
      return;
    }

    if (mode === "chat") {
      DiscourseURL.container
        ?.lookup("service:chat-state-manager")
        ?.prefersFullPage();
    }

    next(() => DiscourseURL.routeTo(path));
  };

  document.addEventListener(
    "click",
    (event) => {
      const element = event.target.closest(
        `#d-sidebar .sidebar-section[data-section-name="${SIDEBAR_SECTION_NAME}"] button[data-workspace-group-path], #d-sidebar .sidebar-section[data-section-name="${SIDEBAR_SECTION_NAME}"] .sidebar-section-header-text[data-workspace-group-path]`
      );

      if (!element) {
        return;
      }

      handleNavigation(element, event);
    },
    true
  );
}

function scheduleScopedSidebarSync(instance) {
  updateScopedSidebarClasses(instance);

  requestAnimationFrame(() => {
    syncScopedSidebarDom(instance);

    requestAnimationFrame(() => syncScopedSidebarDom(instance));
    setTimeout(() => syncScopedSidebarDom(instance), 200);
  });
}

function patchCategoriesGetter(klass, fallbackGetterName) {
  const descriptor = Object.getOwnPropertyDescriptor(klass.prototype, "categories");

  if (!descriptor?.get || klass.prototype._workspaceGroupsSidebarPatched) {
    return;
  }

  klass.prototype._workspaceGroupsSidebarPatched = true;

  Object.defineProperty(klass.prototype, fallbackGetterName, {
    configurable: true,
    get: descriptor.get,
  });

  Object.defineProperty(klass.prototype, "categories", {
    configurable: true,
    get() {
      const scopedCategories = sidebarScopedCategories(this);

      if (!scopedCategories) {
        return this[fallbackGetterName];
      }

      return userSelectedScopedCategories(this, scopedCategories) ?? scopedCategories;
    },
  });
}

function patchChatChannelsGetter(servicePrototype, getterName, fallbackGetterName) {
  const descriptor = Object.getOwnPropertyDescriptor(servicePrototype, getterName);

  if (!descriptor?.get || servicePrototype[fallbackGetterName]) {
    return;
  }

  Object.defineProperty(servicePrototype, fallbackGetterName, {
    configurable: true,
    get: descriptor.get,
  });

  Object.defineProperty(servicePrototype, getterName, {
    configurable: true,
    get() {
      const scopedIds = scopedCategoryIds(this);

      if (!scopedIds) {
        return this[fallbackGetterName];
      }

      return this[fallbackGetterName].filter(
        (channel) => channel.isCategoryChannel && scopedIds.has(channel.chatableId)
      );
    },
  });
}

function patchChatChannelsManagerMutation(servicePrototype, methodName) {
  const original = servicePrototype?.[methodName];

  if (
    typeof original !== "function" ||
    servicePrototype[`_workspaceGroupsSidebarPatched_${methodName}`]
  ) {
    return;
  }

  servicePrototype[`_workspaceGroupsSidebarPatched_${methodName}`] = true;

  servicePrototype[methodName] = function (...args) {
    const result = original.apply(this, args);

    Promise.resolve(result).finally(() => scheduleScopedSidebarSync(this));

    return result;
  };
}

class WorkspaceTeamChannelModes extends Component {
  get categoryButtonStyle() {
    return this.#buttonStyle(
      this.args.suffixArgs?.categoryActive,
      !!this.args.suffixArgs?.categoryPath
    );
  }

  get chatButtonStyle() {
    return this.#buttonStyle(
      this.args.suffixArgs?.chatActive,
      !!this.args.suffixArgs?.chatPath
    );
  }

  get containerStyle() {
    return htmlSafe(
      "display:inline-flex;align-items:center;gap:0.125rem;margin-left:auto;flex-shrink:0;"
    );
  }

  get dotStyle() {
    return htmlSafe(
      "position:absolute;top:-0.1rem;right:-0.12rem;display:block;pointer-events:none;"
    );
  }

  get iconStyle() {
    return htmlSafe(
      "position:relative;display:inline-flex;align-items:center;justify-content:center;width:1em;height:1em;"
    );
  }

  #buttonStyle(active, enabled) {
    return htmlSafe(
      [
        "position:relative",
        "display:inline-flex",
        "align-items:center",
        "justify-content:center",
        "width:1.5rem",
        "height:1.5rem",
        "padding:0",
        "border:0",
        "border-radius:999px",
        "background:" +
          (active ? "var(--d-sidebar-active-background)" : "transparent"),
        "color:" + (active ? "var(--d-sidebar-active-color)" : "currentColor"),
        "opacity:" + (enabled ? (active ? "1" : "0.72") : "0.35"),
        "cursor:" + (enabled ? "pointer" : "default"),
        "flex-shrink:0",
      ].join(";")
    );
  }

  <template>
    <span class="workspace-team-channel-modes" style={{this.containerStyle}}>
      <button
        type="button"
        tabindex="-1"
        title={{@suffixArgs.categoryTitle}}
        aria-label={{@suffixArgs.categoryTitle}}
        style={{this.categoryButtonStyle}}
        data-workspace-group-path={{@suffixArgs.categoryPath}}
        data-workspace-group-mode="category"
      >
        <span style={{this.iconStyle}}>
          {{icon "list"}}

          {{#if @suffixArgs.categoryUnread}}
            <span
              class="chat-channel-unread-indicator"
              style={{this.dotStyle}}
            ></span>
          {{/if}}
        </span>
      </button>

      <button
        type="button"
        tabindex="-1"
        title={{@suffixArgs.chatTitle}}
        aria-label={{@suffixArgs.chatTitle}}
        style={{this.chatButtonStyle}}
        data-workspace-group-path={{@suffixArgs.chatPath}}
        data-workspace-group-mode="chat"
      >
        <span style={{this.iconStyle}}>
          {{icon "d-chat"}}

          {{#if @suffixArgs.chatUnread}}
            <span
              class="chat-channel-unread-indicator"
              style={{this.dotStyle}}
            ></span>
          {{/if}}
        </span>
      </button>
    </span>
  </template>
}

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  ensureScopedSidebarClickHandler();

  api.addSidebarSection((BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
    const container = api.container;

    const WorkspaceTeamChannelLink = class extends BaseCustomSidebarSectionLink {
      constructor({ category, chatChannelsManager, section }) {
        super(...arguments);
        this.category = category;
        this.chatChannelsManager = chatChannelsManager;
        this.section = section;
        this.categoryLink = new CategorySectionLink({
          category,
          topicTrackingState: section.topicTrackingState,
          currentUser: section.currentUser,
        });
      }

      get pairedChannel() {
        return pairedCategoryChannelFor(this.category, this.chatChannelsManager);
      }

      get categoryHasUnread() {
        return !!this.categoryLink.activeCountable;
      }

      get chatHasUnread() {
        return (
          this.pairedChannel &&
          (this.pairedChannel.tracking.unreadCount > 0 ||
            this.pairedChannel.unreadThreadsCountSinceLastViewed > 0 ||
            this.pairedChannel.tracking.mentionCount > 0 ||
            this.pairedChannel.tracking.watchedThreadsUnreadCount > 0)
        );
      }

      get isChatMode() {
        return this.section.mode === "chat";
      }

      get isActive() {
        return this.section.activeCategoryId === this.category.id;
      }

      get name() {
        return `workspace-team-channel-${this.category.id}`;
      }

      get classNames() {
        return [
          "workspace-team-channel-link",
          this.isActive ? "sidebar-section-link--active" : null,
        ]
          .filter(Boolean)
          .join(" ");
      }

      get route() {
        if (this.isChatMode && this.pairedChannel) {
          return "chat.channel";
        }

        return this.categoryLink.route;
      }

      get model() {
        if (this.isChatMode && this.pairedChannel) {
          return null;
        }

        return this.categoryLink.model;
      }

      get models() {
        if (this.isChatMode && this.pairedChannel) {
          return this.pairedChannel.routeModels;
        }

        return null;
      }

      get currentWhen() {
        return this.isChatMode ? CHAT_CURRENT_WHEN : CATEGORY_CURRENT_WHEN;
      }

      get query() {
        if (this.isChatMode) {
          return null;
        }

        return this.categoryLink.query;
      }

      get text() {
        return this.categoryLink.text;
      }

      get title() {
        return this.categoryLink.title || this.category.displayName;
      }

      get prefixType() {
        return this.categoryLink.prefixType;
      }

      get prefixValue() {
        return this.categoryLink.prefixValue;
      }

      get prefixColor() {
        return this.categoryLink.prefixColor;
      }

      get prefixBadge() {
        return this.categoryLink.prefixBadge;
      }

      get suffixComponent() {
        return WorkspaceTeamChannelModes;
      }

      get suffixArgs() {
        return {
          categoryActive: this.isActive && !this.isChatMode,
          categoryPath: this.category.path,
          categoryTitle: `Open ${this.category.displayName} topics`,
          categoryUnread: this.categoryHasUnread,
          chatActive: this.isActive && this.isChatMode,
          chatPath: this.pairedChannel
            ? `/chat/c/${this.pairedChannel.routeModels.join("/")}`
            : null,
          chatTitle: `Open ${this.category.displayName} chat`,
          chatUnread: this.chatHasUnread,
        };
      }

      refreshCounts() {
        this.categoryLink.refreshCounts();
      }

      get keywords() {
        return {
          navigation: [
            this.category.displayName.toLowerCase(),
            this.category.parentCategory?.displayName?.toLowerCase(),
          ].filter(Boolean),
        };
      }
    };

    return class WorkspaceTeamSection extends BaseCustomSidebarSection {
      constructor() {
        super(...arguments);

        this.chatChannelsManager = container.lookup(
          "service:chat-channels-manager"
        );
        this.chat = container.lookup("service:chat");
        this.linkCache = new Map();
        this.currentUser = container.lookup("service:current-user");
        this.router = container.lookup("service:router");
        this.site = container.lookup("service:site");
        this.siteSettings = container.lookup("service:site-settings");
        this.topicTrackingState = container.lookup("service:topic-tracking-state");
        this.callbackId = this.topicTrackingState.onStateChange(() =>
          this.links.forEach((link) => link.refreshCounts())
        );
      }

      willDestroy() {
        if (this.callbackId) {
          this.topicTrackingState.offStateChange(this.callbackId);
        }
      }

      get channelCategories() {
        return sidebarChannelCategories(this) ?? [];
      }

      get workspaceCategory() {
        return sidebarWorkspaceCategory(this);
      }

      get activeCategoryId() {
        return currentScopedCategory(this)?.id;
      }

      get mode() {
        return currentScopedMode(this);
      }

      get name() {
        return SIDEBAR_SECTION_NAME;
      }

      get title() {
        return this.workspaceCategory?.displayName ?? "team";
      }

      get text() {
        return this.workspaceCategory?.displayName ?? "team";
      }

      get actions() {
        if (!this.workspaceCategory) {
          return [];
        }

        const workspaces = memberWorkspaceCategories(this);

        if (workspaces.length <= 1) {
          return [];
        }

        return workspaces.map((workspace) => ({
          id: `open-workspace-${workspace.id}`,
          title: workspace.displayName,
          action: () => DiscourseURL.routeTo(workspaceOverviewPath(workspace)),
        }));
      }

      get actionsIcon() {
        return "users";
      }

      get links() {
        const categoryIds = new Set(
          this.channelCategories.map((category) => category.id)
        );

        for (const linkId of this.linkCache.keys()) {
          if (!categoryIds.has(linkId)) {
            this.linkCache.delete(linkId);
          }
        }

        return this.channelCategories.map((category) => {
          if (!this.linkCache.has(category.id)) {
            this.linkCache.set(
              category.id,
              new WorkspaceTeamChannelLink({
                category,
                chatChannelsManager: this.chatChannelsManager,
                section: this,
              })
            );
          }

          return this.linkCache.get(category.id);
        });
      }

      get displaySection() {
        return true;
      }
    };
  });

  patchCategoriesGetter(
    SidebarUserCategoriesSection,
    "_workspaceGroupsSidebarFallbackCategories"
  );
  patchCategoriesGetter(
    SidebarAnonymousCategoriesSection,
    "_workspaceGroupsSidebarFallbackCategories"
  );

  const chatChannelsManager = api.container.lookup("service:chat-channels-manager");
  const chatChannelsManagerPrototype = chatChannelsManager?.constructor?.prototype;

  if (chatChannelsManagerPrototype) {
    patchChatChannelsGetter(
      chatChannelsManagerPrototype,
      "unstarredPublicMessageChannels",
      "_workspaceGroupsSidebarFallbackUnstarredPublicMessageChannels"
    );
    patchChatChannelsGetter(
      chatChannelsManagerPrototype,
      "unstarredPublicMessageChannelsByActivity",
      "_workspaceGroupsSidebarFallbackUnstarredPublicMessageChannelsByActivity"
    );
    patchChatChannelsManagerMutation(chatChannelsManagerPrototype, "follow");
    patchChatChannelsManagerMutation(chatChannelsManagerPrototype, "remove");
    patchChatChannelsManagerMutation(chatChannelsManagerPrototype, "store");
  }

  api.onPageChange(() => scheduleScopedSidebarSync(api.container));
  scheduleScopedSidebarSync(api.container);
});
