import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { block } from "discourse/blocks";
import SectionHeader from "discourse/components/sidebar/section-header";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import {
  getCollapsedSidebarSectionKey,
  getSidebarSectionContentId,
} from "discourse/lib/sidebar/helpers";
import CategorySectionLink from "discourse/lib/sidebar/user/categories-section/category-section-link";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";
import WorkspaceTeamSidebarRow from "../components/workspace-team-sidebar-row";
import {
  currentScopedCategory,
  currentScopedMode,
  currentWorkspaceCategory,
  chatChannelHasUnread,
  memberWorkspaceCategories,
  pairedCategoryChannelFor,
  sidebarChannelCategories,
  sidebarWorkspaceCategory,
  workspaceSidebarChannelOrder,
  workspaceSidebarLayout,
  workspaceCategoryModeEnabled,
  workspaceChatModeEnabled,
  workspaceOverviewPath,
} from "../lib/workspace-team-sidebar-state";

const WORKSPACE_FOCUS_KEY = "workspace-groups:focused-workspace-id";
const WORKSPACE_NAV_HINT_KEY = "workspace-groups:navigation-hint-seen";
const OTHER_SECTION_ID = "__other";

@block("discourse-workspace-groups:workspace-team-sidebar")
export default class WorkspaceTeamSidebarBlock extends Component {
  @service chat;
  @service("chat-channels-manager") chatChannelsManager;
  @service currentUser;
  @service keyValueStore;
  @service router;
  @service site;
  @service sidebarState;
  @service("site-settings") siteSettings;
  @service("topic-tracking-state") topicTrackingState;

  @tracked topicCountsVersion = 0;
  @tracked chatHydrationVersion = 0;
  @tracked draggedCategoryId = null;
  @tracked editingSidebar = false;
  @tracked headerActionsMenuOpen = false;
  @tracked orderedChannelIds = null;
  @tracked sidebarSectionsOverride = null;
  @tracked savingSidebarOrder = false;
  @tracked showUnreadOnly = false;
  @tracked workspaceNavigationHintSeen = false;
  @tracked workspaceSidebarFocusId = null;

  sectionName = "workspace-team";
  sidebarSectionContentId = getSidebarSectionContentId(this.sectionName);
  collapsedSidebarSectionKey = getCollapsedSidebarSectionKey(this.sectionName);
  focusedSidebarClass = "workspace-team-sidebar--focused";
  unreadOnlySidebarClass = "workspace-team-sidebar--unread-only";

  constructor() {
    super(...arguments);

    this.workspaceSidebarFocusId = this.readWorkspaceSidebarFocusId();
    this.workspaceNavigationHintSeen =
      this.readWorkspaceNavigationHintSeen();
    this.linkCache = new Map();
    this.workspaceChatChannelsByCategoryId = new Map();
    this.workspaceChatIdsByWorkspaceId = new Map();
    this.hydratedWorkspaceChatIds = new Set();
    this.hydratingWorkspaceChatIds = new Set();
    this.failedWorkspaceChatHydrationIds = new Set();
    this.hydratedWorkspaceChatTrackingIds = new Set();
    this.hydratingWorkspaceChatTrackingIds = new Set();
    this.failedWorkspaceChatTrackingIds = new Set();
    this.routeDidChangeCallback = () => this.updateSidebarFocus();
    this.router.on("routeDidChange", this.routeDidChangeCallback);
    this.topicTrackingCallbackId = this.topicTrackingState.onStateChange(() => {
      this.topicCountsVersion++;
      this.rows.forEach((row) => row.categoryLink.refreshCounts());
    });
  }

  willDestroy() {
    super.willDestroy(...arguments);

    this.sidebarSectionsElement?.classList.remove(this.focusedSidebarClass);
    this.sidebarSectionsElement?.classList.remove(this.unreadOnlySidebarClass);
    this.router.off("routeDidChange", this.routeDidChangeCallback);

    if (this.topicTrackingCallbackId) {
      this.topicTrackingState.offStateChange(this.topicTrackingCallbackId);
    }
  }

  get isCollapsed() {
    return this.keyValueStore.getItem(this.collapsedSidebarSectionKey) === "true";
  }

  get displaySectionContent() {
    if (this.sidebarState.filter) {
      return true;
    }

    return !(
      this.sidebarState.collapsedSections.has(this.collapsedSidebarSectionKey) ||
      this.isCollapsed
    );
  }

  get headerCaretIcon() {
    return this.displaySectionContent ? "angle-down" : "angle-right";
  }

  get services() {
    return {
      chat: this.chat,
      chatChannelsManager: this.chatChannelsManager,
      currentUser: this.currentUser,
      router: this.router,
      site: this.site,
      siteSettings: this.siteSettings,
      topicCategory: this.topicCategory,
    };
  }

  get topicCategory() {
    return this.router.currentRouteName?.startsWith("topic.")
      ? getOwner(this)?.lookup("controller:topic")?.model?.category
      : null;
  }

  get focusedWorkspaceCategory() {
    const focusedWorkspaceId = Number(this.workspaceSidebarFocusId);

    if (!focusedWorkspaceId) {
      return null;
    }

    return (
      this.memberWorkspaces.find(
        (workspace) => Number(workspace.id) === focusedWorkspaceId
      ) ?? null
    );
  }

  get workspaceCategory() {
    if (this.routeIsChatContext && !currentWorkspaceCategory(this.services)) {
      return (
        this.focusedWorkspaceCategory ?? sidebarWorkspaceCategory(this.services)
      );
    }

    return sidebarWorkspaceCategory(this.services);
  }

  get memberWorkspaces() {
    return memberWorkspaceCategories(this.services);
  }

  get routeIsWorkspaceContext() {
    const overviewPath = workspaceOverviewPath(this.workspaceCategory);

    return !!(
      currentWorkspaceCategory(this.services) ||
      overviewPath && this.router.currentURL?.startsWith(overviewPath)
    );
  }

  get routeIsChatContext() {
    return !!(
      this.router.currentRouteName?.startsWith("chat.") ||
      this.router.currentURL?.startsWith("/chat")
    );
  }

  get inWorkspaceContext() {
    const focusedWorkspace = this.focusedWorkspaceCategory;

    return !!(
      this.routeIsWorkspaceContext ||
      (this.routeIsChatContext &&
        focusedWorkspace &&
        Number(focusedWorkspace.id) === Number(this.workspaceCategory?.id))
    );
  }

  get activeCategoryId() {
    return currentScopedCategory(this.services)?.id;
  }

  get mode() {
    return currentScopedMode(this.services);
  }

  categoryLinkFor(category) {
    if (!this.linkCache.has(category.id)) {
      this.linkCache.set(
        category.id,
        new CategorySectionLink({
          category,
          topicTrackingState: this.topicTrackingState,
          currentUser: this.currentUser,
        })
      );
    }

    return this.linkCache.get(category.id);
  }

  normalizeSidebarLayout(layout) {
    const seen = new Set();
    const sections = (layout?.sections ?? []).map((section, index) => {
      const channelIds = (section.channel_ids ?? section.channelIds ?? [])
        .map((channelId) => Number(channelId))
        .filter((channelId) => {
          if (!channelId || seen.has(channelId)) {
            return false;
          }

          seen.add(channelId);
          return true;
        });

      return {
        id: section.id || `section-${index + 1}`,
        title: section.title || "Channels",
        channel_ids: channelIds,
        collapsed: !!section.collapsed,
      };
    });
    const otherChannelIds = (
      layout?.other_channel_ids ??
      layout?.otherChannelIds ??
      []
    )
      .map((channelId) => Number(channelId))
      .filter((channelId) => {
        if (!channelId || seen.has(channelId)) {
          return false;
        }

        seen.add(channelId);
        return true;
      });

    return {
      sections,
      other_channel_ids: otherChannelIds,
      other_collapsed: !!(layout?.other_collapsed ?? layout?.otherCollapsed),
    };
  }

  get storedSidebarLayout() {
    return this.normalizeSidebarLayout(
      workspaceSidebarLayout(this.currentUser, this.workspaceCategory?.id)
    );
  }

  get legacySidebarOrder() {
    return workspaceSidebarChannelOrder(
      this.currentUser,
      this.workspaceCategory?.id
    );
  }

  get currentSidebarLayout() {
    if (this.sidebarSectionsOverride) {
      return this.normalizeSidebarLayout(this.sidebarSectionsOverride);
    }

    const storedLayout = this.storedSidebarLayout;
    if (storedLayout.sections.length > 0) {
      return storedLayout;
    }

    const legacyOrder = this.legacySidebarOrder;
    if (legacyOrder.length > 0) {
      return {
        sections: [
          {
            id: "channels",
            title: "Channels",
            channel_ids: legacyOrder,
            collapsed: false,
          },
        ],
        other_channel_ids: [],
        other_collapsed: false,
      };
    }

    return { sections: [], other_channel_ids: [], other_collapsed: false };
  }

  get sidebarOrderedChannelIds() {
    return this.currentSidebarLayout.sections.flatMap(
      (section) => section.channel_ids
    );
  }

  get rows() {
    this.topicCountsVersion;
    this.chatHydrationVersion;
    this.ensureWorkspaceChatChannels();

    const categories =
      sidebarChannelCategories(
        this.services,
        this.orderedChannelIds ?? this.sidebarOrderedChannelIds
      ) ?? [];
    const categoryIds = new Set(categories.map((category) => category.id));

    for (const linkId of this.linkCache.keys()) {
      if (!categoryIds.has(linkId)) {
        this.linkCache.delete(linkId);
      }
    }

    return categories.map((category) => {
      const categoryLink = this.categoryLinkFor(category);
      const pairedChannel = pairedCategoryChannelFor(
        category,
        this.chatChannelsManager
      );
      const workspaceChatChannel = this.workspaceChatChannelsByCategoryId.get(
        category.id
      );
      const categoryAvailable = workspaceCategoryModeEnabled(category);
      const chatAvailable =
        workspaceChatModeEnabled(category) &&
        !!(pairedChannel || workspaceChatChannel);
      const workspaceChatMembership =
        workspaceChatChannel?.currentUserMembership ??
        workspaceChatChannel?.current_user_membership;
      const chatMuted = !!(
        pairedChannel?.currentUserMembership?.muted ??
        workspaceChatMembership?.muted
      );
      const chatChannel = pairedChannel ?? workspaceChatChannel;
      const chatUnread =
        chatAvailable && !chatMuted && chatChannelHasUnread(chatChannel);
      const chatPath =
        pairedChannel?.routeModels?.length > 0
          ? `/chat/c/${pairedChannel.routeModels.join("/")}`
          : workspaceChatChannel?.slug && workspaceChatChannel?.id
            ? `/chat/c/${workspaceChatChannel.slug}/${workspaceChatChannel.id}`
            : null;

      return {
        category,
        categoryLink,
        categoryUnread:
          categoryAvailable && !chatMuted && !!categoryLink.activeCountable,
        categoryTitle: `Open ${category.displayName} topics`,
        chatPath,
        chatTitle: `Open ${category.displayName} chat`,
        chatUnread,
        chatMuted,
        categoryAvailable,
        chatAvailable,
        isActive: this.activeCategoryId === category.id,
        categoryActive:
          this.mode === "category" && this.activeCategoryId === category.id,
        chatActive:
          this.mode === "chat" && this.activeCategoryId === category.id,
      };
    });
  }

  get filteredRows() {
    if (this.editingSidebar || !this.showUnreadOnly) {
      return this.rows;
    }

    return this.rows.filter(
      (row) => row.categoryUnread || row.chatUnread || row.isActive
    );
  }

  get groupedRows() {
    const rows = this.filteredRows;

    if (!this.editingSidebar && rows.length === 0) {
      return [];
    }

    const rowByCategoryId = new Map(
      rows.map((row) => [Number(row.category.id), row])
    );
    const layout = this.currentSidebarLayout;

    if (layout.sections.length === 0) {
      return [
        {
          id: "__flat",
          title: null,
          rows,
          collapsed: false,
          unread: rows.some((row) => row.categoryUnread || row.chatUnread),
          editable: false,
        },
      ];
    }

    const assignedCategoryIds = new Set();
    const groups = layout.sections.map((section) => {
      const sectionRows = [];

      section.channel_ids.forEach((categoryId) => {
        assignedCategoryIds.add(Number(categoryId));
        const row = rowByCategoryId.get(Number(categoryId));
        if (row) {
          sectionRows.push(row);
        }
      });

      return {
        ...section,
        rows: sectionRows.map((row) => ({
          ...row,
          sidebarSectionId: section.id,
          dragging: Number(row.category.id) === Number(this.draggedCategoryId),
        })),
        collapsed: !this.showUnreadOnly && !!section.collapsed,
        unread: sectionRows.some((row) => row.categoryUnread || row.chatUnread),
        editable: true,
      };
    });

    const otherRows = rows.filter(
      (row) => !assignedCategoryIds.has(Number(row.category.id))
    );
    const otherRowsByCategoryId = new Map(
      otherRows.map((row) => [Number(row.category.id), row])
    );
    const orderedOtherRows = [];
    const orderedOtherCategoryIds = new Set();

    layout.other_channel_ids.forEach((categoryId) => {
      const row = otherRowsByCategoryId.get(Number(categoryId));

      if (row) {
        orderedOtherRows.push(row);
        orderedOtherCategoryIds.add(Number(categoryId));
      }
    });

    otherRows.forEach((row) => {
      if (!orderedOtherCategoryIds.has(Number(row.category.id))) {
        orderedOtherRows.push(row);
      }
    });

    if (orderedOtherRows.length > 0 || this.editingSidebar) {
      groups.push({
        id: OTHER_SECTION_ID,
        title: "Other",
        rows: orderedOtherRows.map((row) => ({
          ...row,
          sidebarSectionId: OTHER_SECTION_ID,
          dragging: Number(row.category.id) === Number(this.draggedCategoryId),
        })),
        collapsed: !this.showUnreadOnly && !!layout.other_collapsed,
        unread: orderedOtherRows.some((row) => row.categoryUnread || row.chatUnread),
        editable: false,
      });
    }

    return groups.filter(
      (group) => this.editingSidebar || group.rows.length > 0 || group.id === OTHER_SECTION_ID
    );
  }

  get headerActions() {
    if (!this.workspaceCategory) {
      return [];
    }

    const actions = [];

    this.memberWorkspaces
      .filter((workspace) => workspace.id !== this.workspaceCategory.id)
      .forEach((workspace) =>
        actions.push({
          id: `open-workspace-${workspace.id}`,
          title: workspace.displayName,
          action: () => {
            this.enterWorkspaceSidebar(workspace);
            DiscourseURL.routeTo(workspaceOverviewPath(workspace));
          },
        })
      );

    actions.push({
      id: "leave-workspace",
      title: "Back to forum",
      action: () => {
        this.exitWorkspaceSidebar();
        DiscourseURL.routeTo("/latest");
      },
    });

    return actions;
  }

  get headerActionsIcon() {
    return "shuffle";
  }

  get headerText() {
    return this.inWorkspaceContext
      ? (this.workspaceCategory?.displayName ?? "team")
      : "teams";
  }

  get showWorkspaceNavigationHint() {
    return !!(
      !this.inWorkspaceContext &&
      this.memberWorkspaces.length > 0 &&
      !this.workspaceNavigationHintSeen
    );
  }

  get overviewTitle() {
    return this.workspaceCategory
      ? `Open ${this.workspaceCategory.displayName} overview`
      : null;
  }

  get openWorkspaceTitle() {
    return this.workspaceCategory
      ? `Open ${this.workspaceCategory.displayName} workspace`
      : null;
  }

  get unreadFilterTitle() {
    return this.showUnreadOnly ? "Show all channels" : "Show unread channels";
  }

  workspaceTitle(workspace) {
    return `Open ${workspace.displayName} workspace`;
  }

  readWorkspaceSidebarFocusId() {
    try {
      return sessionStorage.getItem(WORKSPACE_FOCUS_KEY);
    } catch {
      return null;
    }
  }

  readWorkspaceNavigationHintSeen() {
    try {
      return localStorage.getItem(WORKSPACE_NAV_HINT_KEY) === "true";
    } catch {
      return false;
    }
  }

  markWorkspaceNavigationHintSeen() {
    this.workspaceNavigationHintSeen = true;

    try {
      localStorage.setItem(WORKSPACE_NAV_HINT_KEY, "true");
    } catch {
      // Keep the dismissal for this page when persistent storage is unavailable.
    }
  }

  enterWorkspaceSidebar(workspace = this.workspaceCategory) {
    if (!workspace?.id) {
      return;
    }

    this.markWorkspaceNavigationHintSeen();

    const workspaceId = String(workspace.id);
    this.workspaceSidebarFocusId = workspaceId;

    try {
      sessionStorage.setItem(WORKSPACE_FOCUS_KEY, workspaceId);
    } catch {
      // Ignore storage failures; tracked state still controls this tab.
    }
  }

  exitWorkspaceSidebar() {
    this.workspaceSidebarFocusId = null;
    this.showUnreadOnly = false;
    this.editingSidebar = false;
    this.orderedChannelIds = null;
    this.sidebarSectionsOverride = null;

    try {
      sessionStorage.removeItem(WORKSPACE_FOCUS_KEY);
    } catch {
      // Nothing to clean up if storage is unavailable.
    }
  }

  get canEditSidebar() {
    return (
      this.inWorkspaceContext && !!this.workspaceCategory && this.rows.length > 1
    );
  }

  get sidebarEditTitle() {
    return this.editingSidebar
      ? i18n("discourse_workspace_groups.done_editing_sidebar")
      : i18n("discourse_workspace_groups.edit_sidebar");
  }

  updateCurrentUserSidebarOrders(workspaceId, channelIds) {
    const currentOrders = {
      ...(this.currentUser.workspace_sidebar_orders ??
        this.currentUser.workspaceSidebarOrders ??
        {}),
    };

    if (channelIds.length > 0) {
      currentOrders[String(workspaceId)] = channelIds;
    } else {
      delete currentOrders[String(workspaceId)];
    }

    this.currentUser.workspace_sidebar_orders = currentOrders;
    this.currentUser.workspaceSidebarOrders = currentOrders;
  }

  updateCurrentUserSidebarSections(workspaceId, layout) {
    const currentSections = {
      ...(this.currentUser.workspace_sidebar_sections ??
        this.currentUser.workspaceSidebarSections ??
        {}),
    };

    if (layout.sections.length > 0) {
      currentSections[String(workspaceId)] = layout;
    } else {
      delete currentSections[String(workspaceId)];
    }

    this.currentUser.workspace_sidebar_sections = currentSections;
    this.currentUser.workspaceSidebarSections = currentSections;

    const currentOrders = {
      ...(this.currentUser.workspace_sidebar_orders ??
        this.currentUser.workspaceSidebarOrders ??
        {}),
    };
    delete currentOrders[String(workspaceId)];
    this.currentUser.workspace_sidebar_orders = currentOrders;
    this.currentUser.workspaceSidebarOrders = currentOrders;
  }

  editableSidebarLayout() {
    const layout = this.currentSidebarLayout;
    const visibleCategoryIds = new Set(
      this.rows.map((row) => Number(row.category.id))
    );

    if (layout.sections.length === 0) {
      return {
        sections: [
          {
            id: "channels",
            title: "Channels",
            channel_ids: this.rows.map((row) => row.category.id),
            collapsed: false,
          },
        ],
        other_channel_ids: [],
        other_collapsed: false,
      };
    }

    return {
      sections: layout.sections.map((section) => ({
        ...section,
        channel_ids: section.channel_ids.filter((categoryId) =>
          visibleCategoryIds.has(Number(categoryId))
        ),
      })),
      other_channel_ids: layout.other_channel_ids.filter((categoryId) =>
        visibleCategoryIds.has(Number(categoryId))
      ),
      other_collapsed: layout.other_collapsed,
    };
  }

  applySidebarSectionsLocally(nextLayout) {
    const normalizedLayout = this.normalizeSidebarLayout(nextLayout);
    this.sidebarSectionsOverride = normalizedLayout;
    this.orderedChannelIds = normalizedLayout.sections.flatMap(
      (section) => section.channel_ids
    );
  }

  async persistSidebarSections(nextLayout, rollbackLayout = this.sidebarSectionsOverride) {
    if (!this.workspaceCategory || this.savingSidebarOrder) {
      return false;
    }

    const normalizedLayout = this.normalizeSidebarLayout(nextLayout);
    this.applySidebarSectionsLocally(normalizedLayout);
    this.savingSidebarOrder = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.workspaceCategory.id}/sidebar-channels`,
        {
          type: "PUT",
          contentType: "application/json",
          data: JSON.stringify({
            sections: normalizedLayout.sections,
            other_channel_ids: normalizedLayout.other_channel_ids,
            other_collapsed: normalizedLayout.other_collapsed,
          }),
        }
      );
      const savedLayout = this.normalizeSidebarLayout(result.sections);
      this.sidebarSectionsOverride = savedLayout;
      this.orderedChannelIds = savedLayout.sections.flatMap(
        (section) => section.channel_ids
      );
      this.updateCurrentUserSidebarSections(this.workspaceCategory.id, savedLayout);
      return true;
    } catch (error) {
      this.sidebarSectionsOverride = rollbackLayout;
      this.orderedChannelIds = rollbackLayout?.sections?.flatMap(
        (section) => section.channel_ids
      ) ?? null;
      popupAjaxError(error);
      return false;
    } finally {
      this.savingSidebarOrder = false;
    }
  }

  chatChannelById(channelId) {
    return this.chatChannelsManager.channels.find(
      (channel) => Number(channel.id) === Number(channelId)
    );
  }

  applyTrackingState(channel, state) {
    if (!channel?.tracking) {
      return;
    }

    channel.tracking.unreadCount = state?.unread_count ?? 0;
    channel.tracking.mentionCount = state?.mention_count ?? 0;
    channel.tracking.watchedThreadsUnreadCount =
      state?.watched_threads_unread_count ?? 0;
  }

  applyWorkspaceChatTracking(workspaceId, channelTracking = {}) {
    const chatChannelIds = this.workspaceChatIdsByWorkspaceId.get(workspaceId);

    chatChannelIds?.forEach((chatChannelId) => {
      this.applyTrackingState(
        this.chatChannelById(chatChannelId),
        channelTracking[String(chatChannelId)] ?? channelTracking[chatChannelId]
      );
    });

    this.chatHydrationVersion++;
  }

  storeWorkspaceChatChannels(workspaceId, channels) {
    const chatChannelIds = new Set();

    channels.forEach((channel) => {
      if (channel?.chat_channel) {
        this.workspaceChatChannelsByCategoryId.set(
          Number(channel.id),
          channel.chat_channel
        );
        chatChannelIds.add(Number(channel.chat_channel.id));
        this.chatChannelsManager.store(channel.chat_channel, { replace: true });
      }
    });

    this.workspaceChatIdsByWorkspaceId.set(workspaceId, chatChannelIds);
  }

  ensureWorkspaceChatChannels() {
    const workspaceId = this.workspaceCategory?.id;

    if (
      !workspaceId ||
      this.hydratedWorkspaceChatIds.has(workspaceId) ||
      this.hydratingWorkspaceChatIds.has(workspaceId) ||
      this.failedWorkspaceChatHydrationIds.has(workspaceId)
    ) {
      return;
    }

    this.hydratingWorkspaceChatIds.add(workspaceId);

    ajax(`/workspace-groups/workspaces/${workspaceId}`)
      .then((payload) => {
        this.storeWorkspaceChatChannels(workspaceId, payload.channels ?? []);
        this.hydratedWorkspaceChatIds.add(workspaceId);
        this.chatHydrationVersion++;
        this.ensureWorkspaceChatTracking(workspaceId);
      })
      .catch(() => {
        this.failedWorkspaceChatHydrationIds.add(workspaceId);
      })
      .finally(() => {
        this.hydratingWorkspaceChatIds.delete(workspaceId);
      });
  }

  ensureWorkspaceChatTracking(workspaceId = this.workspaceCategory?.id) {
    if (
      !workspaceId ||
      !this.hydratedWorkspaceChatIds.has(workspaceId) ||
      this.hydratedWorkspaceChatTrackingIds.has(workspaceId) ||
      this.hydratingWorkspaceChatTrackingIds.has(workspaceId) ||
      this.failedWorkspaceChatTrackingIds.has(workspaceId)
    ) {
      return;
    }

    this.hydratingWorkspaceChatTrackingIds.add(workspaceId);

    ajax(`/workspace-groups/workspaces/${workspaceId}/chat-tracking`)
      .then((payload) => {
        this.applyWorkspaceChatTracking(
          workspaceId,
          payload.channel_tracking ?? {}
        );
        this.hydratedWorkspaceChatTrackingIds.add(workspaceId);
      })
      .catch(() => {
        this.failedWorkspaceChatTrackingIds.add(workspaceId);
      })
      .finally(() => {
        this.hydratingWorkspaceChatTrackingIds.delete(workspaceId);
      });
  }

  @action
  initializeSidebar(element) {
    this.sidebarSectionsElement = element.closest(".sidebar-sections");
    this.updateSidebarFocus();

    if (this.sidebarState.filter) {
      return;
    }

    if (this.isCollapsed) {
      this.sidebarState.collapseSection(this.sectionName);
    } else {
      this.sidebarState.expandSection(this.sectionName);
    }
  }

  updateSidebarFocus() {
    if (this.routeIsWorkspaceContext) {
      this.enterWorkspaceSidebar(this.workspaceCategory);
    }

    this.sidebarSectionsElement?.classList.toggle(
      this.focusedSidebarClass,
      this.inWorkspaceContext
    );
    this.sidebarSectionsElement?.classList.toggle(
      this.unreadOnlySidebarClass,
      this.inWorkspaceContext && this.showUnreadOnly
    );
  }

  @action
  toggleSectionDisplay(_, event) {
    if (this.displaySectionContent) {
      this.sidebarState.collapseSection(this.sectionName);
    } else {
      this.sidebarState.expandSection(this.sectionName);
    }

    if (!event?.key) {
      document.activeElement?.blur?.();
    }
  }

  @action
  openOverview() {
    if (!this.workspaceCategory) {
      return;
    }

    this.enterWorkspaceSidebar(this.workspaceCategory);
    DiscourseURL.routeTo(workspaceOverviewPath(this.workspaceCategory));
  }

  @action
  openWorkspace(workspace) {
    this.enterWorkspaceSidebar(workspace);
    DiscourseURL.routeTo(workspaceOverviewPath(workspace));
  }

  @action
  toggleHeaderActionsMenu() {
    this.headerActionsMenuOpen = !this.headerActionsMenuOpen;
  }

  @action
  runHeaderAction(headerAction) {
    this.headerActionsMenuOpen = false;
    headerAction.action();
  }

  @action
  dismissWorkspaceNavigationHint() {
    this.markWorkspaceNavigationHintSeen();
  }

  @action
  async toggleSidebarEditing() {
    if (!this.canEditSidebar) {
      return;
    }

    this.showUnreadOnly = false;

    if (this.editingSidebar) {
      const saved = await this.persistSidebarSections(
        this.sidebarSectionsOverride,
        this.currentSidebarLayout
      );

      if (!saved) {
        return;
      }

      this.editingSidebar = false;
      this.orderedChannelIds = null;
      this.sidebarSectionsOverride = null;
      return;
    }

    this.editingSidebar = true;
    this.sidebarSectionsOverride = this.editableSidebarLayout();
    this.orderedChannelIds = this.sidebarSectionsOverride.sections.flatMap(
      (section) => section.channel_ids
    );
  }

  @action
  toggleUnreadFilter() {
    if (this.editingSidebar) {
      return;
    }

    this.showUnreadOnly = !this.showUnreadOnly;
    this.updateSidebarFocus();
  }

  @action
  setDraggedCategory(category) {
    this.draggedCategoryId = category?.id ? Number(category.id) : null;
  }

  @action
  allowDropSlot(event) {
    if (!this.editingSidebar || this.savingSidebarOrder || !this.workspaceCategory) {
      return;
    }

    event.preventDefault();
    event.currentTarget.classList.add(
      "workspace-team-sidebar__drop-slot--active"
    );
  }

  @action
  leaveDropSlot(event) {
    event.currentTarget.classList.remove(
      "workspace-team-sidebar__drop-slot--active"
    );
  }

  @action
  dropOnSidebarSlot(sectionId, targetCategoryId, event) {
    if (!this.editingSidebar || this.savingSidebarOrder || !this.workspaceCategory) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    event.currentTarget.classList.remove(
      "workspace-team-sidebar__drop-slot--active"
    );

    const currentLayout = this.normalizeSidebarLayout(this.sidebarSectionsOverride);
    const draggedCategoryId = Number(this.draggedCategoryId);
    const normalizedTargetCategoryId = Number(targetCategoryId);

    if (!draggedCategoryId || draggedCategoryId === normalizedTargetCategoryId) {
      return;
    }

    const nextLayout = this.moveCategoryInSidebarLayout(
      currentLayout,
      draggedCategoryId,
      sectionId,
      normalizedTargetCategoryId || null
    );

    this.applySidebarSectionsLocally(nextLayout);
  }

  moveCategoryInSidebarLayout(
    layout,
    categoryId,
    targetSectionId,
    targetCategoryId = null
  ) {
    const nextLayout = this.removeCategoryFromSidebarLayout(layout, categoryId);

    if (targetSectionId === OTHER_SECTION_ID) {
      const otherChannelIds = [...nextLayout.other_channel_ids];
      const targetIndex = otherChannelIds.indexOf(Number(targetCategoryId));
      const insertIndex = targetIndex < 0 ? otherChannelIds.length : targetIndex;
      otherChannelIds.splice(insertIndex, 0, categoryId);

      return { ...nextLayout, other_channel_ids: otherChannelIds };
    }

    return {
      ...nextLayout,
      sections: nextLayout.sections.map((section) => {
        if (section.id !== targetSectionId) {
          return section;
        }

        const channelIds = [...section.channel_ids];
        const targetIndex = channelIds.indexOf(Number(targetCategoryId));
        const insertIndex =
          targetIndex < 0 ? channelIds.length : targetIndex;
        channelIds.splice(insertIndex, 0, categoryId);

        return { ...section, channel_ids: channelIds };
      }),
    };
  }

  removeCategoryFromSidebarLayout(layout, categoryId) {
    return {
      ...layout,
      sections: layout.sections.map((section) => ({
        ...section,
        channel_ids: section.channel_ids.filter(
          (sectionCategoryId) => Number(sectionCategoryId) !== Number(categoryId)
        ),
      })),
      other_channel_ids: layout.other_channel_ids.filter(
        (sectionCategoryId) => Number(sectionCategoryId) !== Number(categoryId)
      ),
    };
  }

  @action
  async toggleSidebarSection(section) {
    const currentLayout = this.normalizeSidebarLayout(this.currentSidebarLayout);
    const nextLayout = {
      ...currentLayout,
      sections: currentLayout.sections.map((currentSection) =>
        currentSection.id === section.id
          ? { ...currentSection, collapsed: !currentSection.collapsed }
          : currentSection
      ),
      other_collapsed:
        section.id === OTHER_SECTION_ID
          ? !currentLayout.other_collapsed
          : currentLayout.other_collapsed,
    };

    if (this.editingSidebar) {
      this.applySidebarSectionsLocally(nextLayout);
      return;
    }

    await this.persistSidebarSections(nextLayout, currentLayout);
  }

  @action
  async addSidebarSection() {
    if (!this.editingSidebar || this.savingSidebarOrder) {
      return;
    }

    const title = window.prompt("Section name");
    if (!title?.trim()) {
      return;
    }

    const currentLayout = this.normalizeSidebarLayout(this.sidebarSectionsOverride);
    const nextLayout = {
      ...currentLayout,
      sections: [
        ...currentLayout.sections,
        {
          id: `section-${Date.now()}`,
          title: title.trim(),
          channel_ids: [],
          collapsed: false,
        },
      ],
    };

    this.applySidebarSectionsLocally(nextLayout);
  }

  @action
  async renameSidebarSection(section) {
    if (!this.editingSidebar || this.savingSidebarOrder || !section.editable) {
      return;
    }

    const title = window.prompt("Section name", section.title);
    if (!title?.trim()) {
      return;
    }

    const currentLayout = this.normalizeSidebarLayout(this.sidebarSectionsOverride);
    const nextLayout = {
      ...currentLayout,
      sections: currentLayout.sections.map((currentSection) =>
        currentSection.id === section.id
          ? { ...currentSection, title: title.trim() }
          : currentSection
      ),
    };

    this.applySidebarSectionsLocally(nextLayout);
  }

  @action
  async deleteSidebarSection(section) {
    if (!this.editingSidebar || this.savingSidebarOrder || !section.editable) {
      return;
    }

    const currentLayout = this.normalizeSidebarLayout(this.sidebarSectionsOverride);
    const nextLayout = {
      ...currentLayout,
      sections: currentLayout.sections.filter(
        (currentSection) => currentSection.id !== section.id
      ),
    };

    this.applySidebarSectionsLocally(nextLayout);
  }

  <template>
    <div
      {{didInsert this.initializeSidebar}}
      data-section-name={{this.sectionName}}
      class={{concatClass
        "sidebar-section"
        "sidebar-section-wrapper"
        "workspace-team-sidebar"
        (if
          this.draggedCategoryId
          "workspace-team-sidebar--dragging"
        )
        (if
          this.displaySectionContent
          "sidebar-section--expanded"
          "sidebar-section--collapsed"
        )
      }}
    >
      <div class="sidebar-section-header-wrapper sidebar-row">
        <SectionHeader
          @collapsable={{true}}
          @sidebarSectionContentId={{this.sidebarSectionContentId}}
          @toggleSectionDisplay={{this.toggleSectionDisplay}}
          @isExpanded={{this.displaySectionContent}}
        >
          <span class="sidebar-section-header-caret">
            {{icon this.headerCaretIcon}}
          </span>

          <span class="sidebar-section-header-text">
            {{this.headerText}}
          </span>
        </SectionHeader>

        {{#if this.inWorkspaceContext}}
          <div class="workspace-team-sidebar__header-switcher">
            <button
              type="button"
              title="Switch workspace"
              aria-label="Switch workspace"
              aria-haspopup="menu"
              aria-expanded={{if this.headerActionsMenuOpen "true" "false"}}
              class="workspace-team-sidebar__header-switcher-button"
              {{on "click" this.toggleHeaderActionsMenu}}
            >
              {{icon this.headerActionsIcon}}
            </button>
            {{#if this.headerActionsMenuOpen}}
              <ul class="workspace-team-sidebar__header-switcher-menu">
                {{#each this.headerActions as |headerAction|}}
                  <li>
                    <button
                      type="button"
                      {{on "click" (fn this.runHeaderAction headerAction)}}
                    >
                      {{headerAction.title}}
                    </button>
                  </li>
                {{/each}}
              </ul>
            {{/if}}
          </div>
        {{/if}}
      </div>

      {{#if this.inWorkspaceContext}}
        <div class="workspace-team-sidebar__controls">
          <button
            type="button"
            title={{this.overviewTitle}}
            aria-label={{this.overviewTitle}}
            class="workspace-team-sidebar__control"
            {{on "click" this.openOverview}}
          >
            {{icon "layer-group"}}
            <span>Overview</span>
          </button>

          <button
            type="button"
            title={{this.unreadFilterTitle}}
            aria-label={{this.unreadFilterTitle}}
            aria-pressed={{if this.showUnreadOnly "true" "false"}}
            class={{concatClass
              "workspace-team-sidebar__control"
              (if
                this.showUnreadOnly
                "workspace-team-sidebar__control--active"
              )
            }}
            disabled={{this.editingSidebar}}
            {{on "click" this.toggleUnreadFilter}}
          >
            {{icon "filter"}}
            <span>Unread</span>
          </button>

          {{#if this.canEditSidebar}}
            {{#if this.editingSidebar}}
              <button
                type="button"
                title="Add section"
                aria-label="Add section"
                class="workspace-team-sidebar__control"
                disabled={{this.savingSidebarOrder}}
                {{on "click" this.addSidebarSection}}
              >
                {{icon "plus"}}
                <span>Section</span>
              </button>
            {{/if}}

            <button
              type="button"
              title={{this.sidebarEditTitle}}
              aria-label={{this.sidebarEditTitle}}
              class="workspace-team-sidebar__control"
              disabled={{this.savingSidebarOrder}}
              {{on "click" this.toggleSidebarEditing}}
            >
              {{icon (if this.editingSidebar "check" "pencil")}}
              <span>{{if this.editingSidebar "Done" "Edit"}}</span>
            </button>
          {{/if}}
        </div>
      {{/if}}

      {{#if this.displaySectionContent}}
        {{#if this.showWorkspaceNavigationHint}}
          <div class="workspace-team-sidebar__hint">
            <p>
              Open a team to focus this sidebar on its channels and DMs.
            </p>
            <button
              type="button"
              class="workspace-team-sidebar__hint-dismiss"
              {{on "click" this.dismissWorkspaceNavigationHint}}
            >
              Got it
            </button>
          </div>
        {{/if}}

        <ul
          id={{this.sidebarSectionContentId}}
          class="sidebar-section-content"
        >
          {{#if this.inWorkspaceContext}}
            {{#each this.groupedRows as |group|}}
              {{#if group.title}}
                <li
                  class="workspace-team-sidebar__section"
                >
                  <button
                    type="button"
                    class={{concatClass
                      "workspace-team-sidebar__section-heading"
                      (if
                        group.unread
                        "workspace-team-sidebar__section-heading--unread"
                      )
                    }}
                    {{on "click" (fn this.toggleSidebarSection group)}}
                  >
                    {{icon (if group.collapsed "angle-right" "angle-down")}}
                    <span>{{group.title}}</span>
                    {{#if group.unread}}
                      <span class="chat-channel-unread-indicator"></span>
                    {{/if}}
                  </button>

                  {{#if this.editingSidebar}}
                    {{#if group.editable}}
                      <button
                        type="button"
                        title="Rename section"
                        aria-label="Rename section"
                        class="workspace-team-sidebar__section-action"
                        disabled={{this.savingSidebarOrder}}
                        {{on "click" (fn this.renameSidebarSection group)}}
                      >
                        {{icon "pencil"}}
                      </button>
                      <button
                        type="button"
                        title="Delete section"
                        aria-label="Delete section"
                        class="workspace-team-sidebar__section-action"
                        disabled={{this.savingSidebarOrder}}
                        {{on "click" (fn this.deleteSidebarSection group)}}
                      >
                        {{icon "trash-alt"}}
                      </button>
                    {{/if}}
                  {{/if}}
                </li>
              {{/if}}

              {{#unless group.collapsed}}
                {{#if this.editingSidebar}}
                  {{#unless group.rows.length}}
                    <li
                      class="workspace-team-sidebar__drop-slot workspace-team-sidebar__drop-slot--empty"
                      {{on "dragover" this.allowDropSlot}}
                      {{on "dragleave" this.leaveDropSlot}}
                      {{on "drop" (fn this.dropOnSidebarSlot group.id null)}}
                    >
                      {{icon "hand-paper"}}
                      <span>Drag channels here</span>
                    </li>
                  {{/unless}}
                {{/if}}

                {{#each group.rows as |row|}}
                  {{#if this.editingSidebar}}
                    <li
                      class="workspace-team-sidebar__drop-slot"
                      {{on "dragover" this.allowDropSlot}}
                      {{on "dragleave" this.leaveDropSlot}}
                      {{on "drop" (fn this.dropOnSidebarSlot group.id row.category.id)}}
                    ></li>
                  {{/if}}

                  <WorkspaceTeamSidebarRow
                    @categoryLink={{row.categoryLink}}
                    @categoryUnread={{row.categoryUnread}}
                    @categoryTitle={{row.categoryTitle}}
                    @chatPath={{row.chatPath}}
                    @chatTitle={{row.chatTitle}}
                    @chatUnread={{row.chatUnread}}
                    @chatMuted={{row.chatMuted}}
                    @categoryAvailable={{row.categoryAvailable}}
                    @chatAvailable={{row.chatAvailable}}
                    @isActive={{row.isActive}}
                    @categoryActive={{row.categoryActive}}
                    @chatActive={{row.chatActive}}
                    @editable={{this.editingSidebar}}
                    @dragging={{row.dragging}}
                    @sectionId={{row.sidebarSectionId}}
                    @setDraggedCategory={{this.setDraggedCategory}}
                  />
                {{/each}}

                {{#if this.editingSidebar}}
                  {{#if group.rows.length}}
                    <li
                      class="workspace-team-sidebar__drop-slot"
                      {{on "dragover" this.allowDropSlot}}
                      {{on "dragleave" this.leaveDropSlot}}
                      {{on "drop" (fn this.dropOnSidebarSlot group.id null)}}
                    ></li>
                  {{/if}}
                {{/if}}
              {{/unless}}
            {{else}}
              <li class="workspace-team-sidebar__empty">
                No unread channels
              </li>
            {{/each}}
          {{else}}
            {{#each this.memberWorkspaces as |workspace|}}
              <li class="sidebar-section-link-wrapper">
                <button
                  type="button"
                  title={{this.workspaceTitle workspace}}
                  aria-label={{this.workspaceTitle workspace}}
                  class="sidebar-section-link sidebar-row workspace-team-sidebar__workspace-link"
                  {{on "click" (fn this.openWorkspace workspace)}}
                >
                  <span class="sidebar-section-link-prefix icon">
                    {{icon "users"}}
                  </span>
                  <span class="sidebar-section-link-content-text">
                    {{workspace.displayName}}
                  </span>
                </button>
              </li>
            {{/each}}
          {{/if}}
        </ul>
      {{/if}}
    </div>
  </template>
}
