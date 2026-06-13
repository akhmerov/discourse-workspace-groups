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
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import {
  getCollapsedSidebarSectionKey,
  getSidebarSectionContentId,
} from "discourse/lib/sidebar/helpers";
import CategorySectionLink from "discourse/lib/sidebar/user/categories-section/category-section-link";
import DiscourseURL from "discourse/lib/url";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import WorkspaceTeamSidebarRow from "../components/workspace-team-sidebar-row";
import {
  channelIdsForLayout,
  deleteSidebarSection as deleteSidebarSectionFromLayout,
  editableSidebarLayout as buildEditableSidebarLayout,
  insertSidebarSection,
  moveCategoryInSidebarLayout,
  moveSidebarSectionInLayout,
  normalizeSidebarLayout,
  OTHER_SECTION_ID,
  renameSidebarSection,
  sidebarLayoutFromState,
  toggleSidebarSectionCollapsed,
  uniqueSidebarSectionId,
} from "../lib/workspace-sidebar-layout";
import {
  chatChannelHasUnread,
  currentScopedCategory,
  currentScopedMode,
  currentWorkspaceCategory,
  focusedWorkspaceCategory as focusedSidebarWorkspaceCategory,
  memberWorkspaceCategories,
  pairedCategoryChannelFor,
  sidebarChannelCategories,
  sidebarWorkspaceCategory,
  WORKSPACE_FOCUS_CHANGED_EVENT,
  WORKSPACE_FOCUS_KEY,
  workspaceCategoryModeEnabled,
  workspaceChatModeEnabled,
  workspaceOverviewPath,
  workspaceSidebarChannelOrder,
  workspaceSidebarLayout,
} from "../lib/workspace-team-sidebar-state";

const WORKSPACE_NAV_HINT_KEY = "workspace-groups:navigation-hint-seen";
const WORKSPACE_SIDEBAR_EDIT_KEY_PREFIX = "workspace-groups:sidebar-edit:";
const SIDEBAR_DRAG_AUTOSCROLL_EDGE_PX = 72;
const SIDEBAR_DRAG_AUTOSCROLL_MAX_SPEED_PX = 18;
const SIDEBAR_DRAG_ACTIVATION_PX = 8;
const SIDEBAR_TOUCH_LONG_PRESS_MS = 350;
const SIDEBAR_TOUCH_SCROLL_SLOP_RATIO = 1.25;

@block("discourse-workspace-groups:workspace-team-sidebar")
export default class WorkspaceTeamSidebarBlock extends Component {
  @service chat;
  @service("chat-channels-manager") chatChannelsManager;
  @service currentUser;
  @service dialog;
  @service keyValueStore;
  @service modal;
  @service router;
  @service site;
  @service sidebarState;
  @service("site-settings") siteSettings;
  @service("topic-tracking-state") topicTrackingState;

  @tracked topicCountsVersion = 0;
  @tracked chatHydrationVersion = 0;
  @tracked draggedCategoryId = null;
  @tracked draggedSidebarSectionId = null;
  @tracked sidebarDropTarget = null;
  @tracked editingSidebar = false;
  @tracked editingSidebarSectionId = null;
  @tracked editingSidebarSectionTitle = "";
  @tracked headerActionsMenuOpen = false;
  @tracked orderedChannelIds = null;
  @tracked sidebarSectionsOverride = null;
  @tracked savingSidebarOrder = false;
  @tracked showUnreadOnly = false;
  @tracked workspaceNavigationHintSeen = false;
  @tracked workspaceSidebarFocusId = null;

  pendingSidebarSectionsSave = null;
  sidebarSectionsSavePromise = null;

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
    this.sidebarPointerMoveCallback = (event) =>
      this.updateSidebarPointerDrag(event);
    this.sidebarPointerUpCallback = (event) =>
      this.finishSidebarPointerDrag(event);
    this.sidebarPointerCancelCallback = () => this.cancelSidebarPointerDrag();
    this.sidebarTouchEndCallback = (event) => this.finishSidebarTouchDrag(event);
    this.sidebarTouchCancelCallback = () => this.cancelSidebarPointerDrag();
    this.sidebarPointerKeydownCallback = (event) => {
      if (event.key === "Escape") {
        this.cancelSidebarPointerDrag();
      }
    };
    this.routeDidChangeCallback = () => this.updateSidebarFocus();
    this.workspaceFocusChangedCallback = (event) => {
      this.applyWorkspaceSidebarFocusId(event.detail?.workspaceId ?? null);
      this.updateSidebarFocus({ syncRouteFocus: false });
    };
    this.router.on("routeDidChange", this.routeDidChangeCallback);
    window.addEventListener(
      WORKSPACE_FOCUS_CHANGED_EVENT,
      this.workspaceFocusChangedCallback
    );
    this.topicTrackingCallbackId = this.topicTrackingState.onStateChange(() => {
      this.topicCountsVersion++;
      this.rows.forEach((row) => row.categoryLink.refreshCounts());
    });
  }

  willDestroy() {
    super.willDestroy(...arguments);

    this.sidebarSectionsElement?.classList.remove(this.focusedSidebarClass);
    this.sidebarSectionsElement?.classList.remove(this.unreadOnlySidebarClass);
    this.cancelSidebarPointerDrag();
    this.router.off("routeDidChange", this.routeDidChangeCallback);
    window.removeEventListener(
      WORKSPACE_FOCUS_CHANGED_EVENT,
      this.workspaceFocusChangedCallback
    );

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
    return focusedSidebarWorkspaceCategory(
      this.services,
      this.workspaceSidebarFocusId
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

  get sidebarLayoutOptions() {
    return {
      defaultSectionTitle: this.defaultChannelGroupTitle,
    };
  }

  get storedSidebarLayout() {
    return normalizeSidebarLayout(
      workspaceSidebarLayout(this.currentUser, this.workspaceCategory?.id),
      this.sidebarLayoutOptions
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
      return normalizeSidebarLayout(
        this.sidebarSectionsOverride,
        this.sidebarLayoutOptions
      );
    }

    return sidebarLayoutFromState(
      this.storedSidebarLayout,
      this.legacySidebarOrder,
      this.sidebarLayoutOptions
    );
  }

  get sidebarOrderedChannelIds() {
    return channelIdsForLayout(this.currentSidebarLayout, this.sidebarLayoutOptions);
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
        categoryTitle: i18n("discourse_workspace_groups.open_channel_topics", {
          name: category.displayName,
        }),
        chatPath,
        chatTitle: i18n("discourse_workspace_groups.open_channel_chat", {
          name: category.displayName,
        }),
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
        title: this.otherChannelGroupTitle,
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
      title: this.routeIsChatContext
        ? i18n("discourse_workspace_groups.back_to_chat_channels")
        : i18n("discourse_workspace_groups.back_to_forum"),
      action: () => {
        this.exitWorkspaceSidebar();

        if (!this.routeIsChatContext) {
          DiscourseURL.routeTo("/latest");
        }
      },
    });

    return actions;
  }

  get headerActionsIcon() {
    return "shuffle";
  }

  get headerText() {
    return this.inWorkspaceContext
      ? (this.workspaceCategory?.displayName ??
          i18n("discourse_workspace_groups.team_sidebar_title"))
      : i18n("discourse_workspace_groups.teams_sidebar_title");
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
      ? i18n("discourse_workspace_groups.open_workspace_overview", {
          name: this.workspaceCategory.displayName,
        })
      : null;
  }

  get openWorkspaceTitle() {
    return this.workspaceCategory
      ? i18n("discourse_workspace_groups.open_workspace", {
          name: this.workspaceCategory.displayName,
        })
      : null;
  }

  get unreadFilterTitle() {
    return this.showUnreadOnly
      ? i18n("discourse_workspace_groups.show_all_channels")
      : i18n("discourse_workspace_groups.show_unread_channels");
  }

  get canOpenChannelFinder() {
    return !!(
      this.chat?.userCanChat &&
      (this.siteSettings.enable_public_channels ||
        this.chat.userCanDirectMessage)
    );
  }

  workspaceTitle(workspace) {
    return i18n("discourse_workspace_groups.open_workspace", {
      name: workspace.displayName,
    });
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

  workspaceSidebarEditKey(workspaceId = this.workspaceCategory?.id) {
    return workspaceId ? `${WORKSPACE_SIDEBAR_EDIT_KEY_PREFIX}${workspaceId}` : null;
  }

  readWorkspaceSidebarEditingState() {
    const key = this.workspaceSidebarEditKey();

    if (!key) {
      return null;
    }

    try {
      return JSON.parse(sessionStorage.getItem(key));
    } catch {
      return null;
    }
  }

  rememberWorkspaceSidebarEditingState(state = {}) {
    const key = this.workspaceSidebarEditKey();

    if (!key) {
      return;
    }

    try {
      sessionStorage.setItem(
        key,
        JSON.stringify({
          editing: this.editingSidebar,
          sectionId: this.editingSidebarSectionId,
          title: this.editingSidebarSectionTitle,
          layout: this.sidebarSectionsOverride,
          ...state,
        })
      );
    } catch {
      // Tracked state still controls this page when storage is unavailable.
    }
  }

  clearWorkspaceSidebarEditingState() {
    const key = this.workspaceSidebarEditKey();

    if (!key) {
      return;
    }

    try {
      sessionStorage.removeItem(key);
    } catch {
      // Nothing to clear if storage is unavailable.
    }
  }

  restoreWorkspaceSidebarEditingState() {
    if (!this.canEditSidebar || this.editingSidebar) {
      return;
    }

    const state = this.readWorkspaceSidebarEditingState();

    if (!state?.editing) {
      return;
    }

    const editableLayout = buildEditableSidebarLayout(
      state.layout ?? this.currentSidebarLayout,
      this.rows,
      this.sidebarLayoutOptions
    );
    this.editingSidebar = true;
    this.showUnreadOnly = false;
    this.sidebarSectionsOverride = editableLayout;
    this.sidebarDropTarget = null;
    this.orderedChannelIds = channelIdsForLayout(
      editableLayout,
      this.sidebarLayoutOptions
    );

    const section = editableLayout.sections.find(
      (candidate) => candidate.id === state.sectionId
    );

    if (section) {
      this.editingSidebarSectionId = section.id;
      this.editingSidebarSectionTitle = state.title ?? section.title;
    }
  }

  applyWorkspaceSidebarFocusId(workspaceId) {
    this.workspaceSidebarFocusId = workspaceId ? String(workspaceId) : null;

    if (this.workspaceSidebarFocusId) {
      return;
    }

    this.showUnreadOnly = false;
    this.editingSidebar = false;
    this.orderedChannelIds = null;
    this.sidebarSectionsOverride = null;
    this.clearWorkspaceSidebarEditingState();
    this.cancelSidebarSectionTitleEdit();
  }

  enterWorkspaceSidebar(workspace = this.workspaceCategory) {
    if (!workspace?.id) {
      return;
    }

    this.markWorkspaceNavigationHintSeen();

    const workspaceId = String(workspace.id);
    this.applyWorkspaceSidebarFocusId(workspaceId);

    try {
      sessionStorage.setItem(WORKSPACE_FOCUS_KEY, workspaceId);
    } catch {
      // Ignore storage failures; tracked state still controls this tab.
    }

    window.dispatchEvent(
      new CustomEvent(WORKSPACE_FOCUS_CHANGED_EVENT, {
        detail: { workspaceId },
      })
    );
  }

  exitWorkspaceSidebar() {
    this.applyWorkspaceSidebarFocusId(null);

    try {
      sessionStorage.removeItem(WORKSPACE_FOCUS_KEY);
    } catch {
      // Nothing to clean up if storage is unavailable.
    }

    window.dispatchEvent(new CustomEvent(WORKSPACE_FOCUS_CHANGED_EVENT));
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

  get addChannelGroupTitle() {
    return i18n("discourse_workspace_groups.add_channel_group");
  }

  get addChannelGroupLabel() {
    return i18n("discourse_workspace_groups.channel_group");
  }

  get defaultChannelGroupTitle() {
    return i18n("discourse_workspace_groups.default_channel_group");
  }

  get otherChannelGroupTitle() {
    return i18n("discourse_workspace_groups.other_channel_group");
  }

  get overviewLabel() {
    return i18n("discourse_workspace_groups.overview_button");
  }

  get unreadLabel() {
    return i18n("discourse_workspace_groups.unread_button");
  }

  get channelFinderTitle() {
    return i18n("discourse_workspace_groups.find_channel");
  }

  get sidebarEditLabel() {
    return this.editingSidebar
      ? i18n("discourse_workspace_groups.done_editing_sidebar_label")
      : i18n("discourse_workspace_groups.edit_sidebar_label");
  }

  get switchWorkspaceTitle() {
    return i18n("discourse_workspace_groups.switch_workspace");
  }

  get workspaceNavigationHint() {
    return i18n("discourse_workspace_groups.workspace_navigation_hint");
  }

  get dismissWorkspaceNavigationHintLabel() {
    return i18n("discourse_workspace_groups.dismiss_workspace_navigation_hint");
  }

  get groupNameLabel() {
    return i18n("discourse_workspace_groups.group_name");
  }

  get saveGroupNameLabel() {
    return i18n("discourse_workspace_groups.save_group_name");
  }

  get cancelGroupRenameLabel() {
    return i18n("discourse_workspace_groups.cancel_group_rename");
  }

  get renameGroupLabel() {
    return i18n("discourse_workspace_groups.rename_group");
  }

  get deleteGroupLabel() {
    return i18n("discourse_workspace_groups.delete_group");
  }

  get dragChannelsHereLabel() {
    return i18n("discourse_workspace_groups.drag_channels_here");
  }

  get noChannelsLabel() {
    return i18n("discourse_workspace_groups.no_channels");
  }

  get noUnreadChannelsLabel() {
    return i18n("discourse_workspace_groups.no_unread_channels");
  }

  get sidebarSectionTitleInvalid() {
    return this.editingSidebarSectionTitle.trim().length === 0;
  }

  get draggingSidebarItem() {
    return this.draggedCategoryId || this.draggedSidebarSectionId;
  }

  get editableGroups() {
    return this.groupedRows.map((group) => ({
      ...group,
      editingTitle:
        group.editable && this.editingSidebarSectionId === group.id,
      draggingSection: group.id === this.draggedSidebarSectionId,
      dropTarget:
        this.sidebarDropTarget?.sectionId === group.id &&
        this.sidebarDropTarget?.type === "channel" &&
        !this.sidebarDropTarget?.categoryId,
      sectionDropBefore:
        this.sidebarDropTarget?.type === "section" &&
        this.sidebarDropTarget?.sectionId === group.id &&
        this.sidebarDropTarget?.position === "before",
      sectionDropAfter:
        this.sidebarDropTarget?.type === "section" &&
        this.sidebarDropTarget?.sectionId === group.id &&
        this.sidebarDropTarget?.position === "after",
      rows: group.rows.map((row) => {
        const targetIsThisRow =
          this.sidebarDropTarget?.sectionId === group.id &&
          this.sidebarDropTarget?.type === "channel" &&
          Number(this.sidebarDropTarget?.categoryId) === Number(row.category.id);

        return {
          ...row,
          dragging: Number(row.category.id) === Number(this.draggedCategoryId),
          dropBefore:
            targetIsThisRow && this.sidebarDropTarget?.position === "before",
          dropAfter:
            targetIsThisRow && this.sidebarDropTarget?.position === "after",
        };
      }),
    }));
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

    if (layout.sections.length > 0 || layout.other_channel_ids.length > 0) {
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

  applySidebarSectionsLocally(nextLayout) {
    const normalizedLayout = normalizeSidebarLayout(
      nextLayout,
      this.sidebarLayoutOptions
    );
    this.sidebarSectionsOverride = normalizedLayout;
    this.orderedChannelIds = channelIdsForLayout(
      normalizedLayout,
      this.sidebarLayoutOptions
    );
  }

  async persistSidebarSections(
    nextLayout,
    rollbackLayout = this.sidebarSectionsOverride
  ) {
    if (!this.workspaceCategory) {
      return false;
    }

    const normalizedLayout = normalizeSidebarLayout(
      nextLayout,
      this.sidebarLayoutOptions
    );
    const normalizedRollbackLayout = rollbackLayout
      ? normalizeSidebarLayout(rollbackLayout, this.sidebarLayoutOptions)
      : null;
    this.applySidebarSectionsLocally(normalizedLayout);
    if (this.editingSidebar) {
      this.rememberWorkspaceSidebarEditingState({
        editing: true,
        layout: normalizedLayout,
      });
    }
    this.pendingSidebarSectionsSave = {
      workspaceId: this.workspaceCategory.id,
      layout: normalizedLayout,
    };

    if (!this.sidebarSectionsSavePromise) {
      this.sidebarSectionsSavePromise = this.flushSidebarSectionsSaveQueue(
        normalizedRollbackLayout
      );
    }

    return this.sidebarSectionsSavePromise;
  }

  async flushSidebarSectionsSaveQueue(rollbackLayout) {
    this.savingSidebarOrder = true;
    let activeSave = null;

    try {
      while (this.pendingSidebarSectionsSave) {
        activeSave = this.pendingSidebarSectionsSave;
        this.pendingSidebarSectionsSave = null;

        const result = await ajax(
          `/workspace-groups/workspaces/${activeSave.workspaceId}/sidebar-channels`,
          {
            type: "PUT",
            contentType: "application/json",
            data: JSON.stringify({
              sections: activeSave.layout.sections,
              other_channel_ids: activeSave.layout.other_channel_ids,
              other_collapsed: activeSave.layout.other_collapsed,
            }),
          }
        );
        const savedLayout = normalizeSidebarLayout(
          result.sections,
          this.sidebarLayoutOptions
        );
        this.updateCurrentUserSidebarSections(
          activeSave.workspaceId,
          savedLayout
        );

        if (
          !this.pendingSidebarSectionsSave &&
          Number(this.workspaceCategory?.id) === Number(activeSave.workspaceId)
        ) {
          this.sidebarSectionsOverride = savedLayout;
          this.orderedChannelIds = channelIdsForLayout(
            savedLayout,
            this.sidebarLayoutOptions
          );
        }
      }

      return true;
    } catch (error) {
      this.pendingSidebarSectionsSave = null;

      const storedLayout = workspaceSidebarLayout(
        this.currentUser,
        activeSave?.workspaceId
      );
      const fallbackLayout = storedLayout
        ? normalizeSidebarLayout(storedLayout, this.sidebarLayoutOptions)
        : rollbackLayout;

      if (
        !activeSave ||
        Number(this.workspaceCategory?.id) === Number(activeSave.workspaceId)
      ) {
        this.sidebarSectionsOverride = fallbackLayout;
        this.orderedChannelIds = fallbackLayout
          ? channelIdsForLayout(fallbackLayout, this.sidebarLayoutOptions)
          : null;
      }

      popupAjaxError(error);
      return false;
    } finally {
      this.savingSidebarOrder = false;
      this.sidebarSectionsSavePromise = null;
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
    this.restoreWorkspaceSidebarEditingState();

    if (this.sidebarState.filter) {
      return;
    }

    if (this.isCollapsed) {
      this.sidebarState.collapseSection(this.sectionName);
    } else {
      this.sidebarState.expandSection(this.sectionName);
    }
  }

  updateSidebarFocus({ syncRouteFocus = true } = {}) {
    if (syncRouteFocus && this.routeIsWorkspaceContext) {
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
  async openChannelFinder() {
    const { default: ChatModalNewMessage } = await import(
      "discourse/plugins/chat/discourse/components/chat/modal/new-message"
    );
    this.modal.show(ChatModalNewMessage);
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
      const rollbackLayout = this.currentSidebarLayout;
      this.applyEditingSidebarSectionTitle();

      const saved = await this.persistSidebarSections(
        this.sidebarSectionsOverride,
        rollbackLayout
      );

      if (!saved) {
        return;
      }

      this.editingSidebar = false;
      this.cancelSidebarSectionTitleEdit();
      this.orderedChannelIds = null;
      this.sidebarSectionsOverride = null;
      this.sidebarDropTarget = null;
      this.clearWorkspaceSidebarEditingState();
      return;
    }

    this.editingSidebar = true;
    const editableLayout = buildEditableSidebarLayout(
      this.currentSidebarLayout,
      this.rows,
      this.sidebarLayoutOptions
    );
    this.sidebarSectionsOverride = editableLayout;
    this.cancelSidebarSectionTitleEdit();
    this.sidebarDropTarget = null;
    this.orderedChannelIds = channelIdsForLayout(
      editableLayout,
      this.sidebarLayoutOptions
    );
    this.rememberWorkspaceSidebarEditingState({
      editing: true,
      layout: editableLayout,
    });
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
  startSidebarPointerDrag(row, event) {
    if (!this.editingSidebar || !this.workspaceCategory) {
      return;
    }

    if (event.pointerType === "mouse" && event.button !== 0) {
      return;
    }

    const rowElement = event.currentTarget.closest(
      ".workspace-team-sidebar__row"
    );

    if (!rowElement) {
      return;
    }

    const rowRect = rowElement.getBoundingClientRect();
    this.beginPendingSidebarPointerDrag({
      type: "channel",
      element: rowElement,
      sourceElement: event.currentTarget,
      pointerId: event.pointerId,
      pointerType: event.pointerType,
      categoryId: Number(row.category.id),
      offsetX: event.clientX - rowRect.left,
      offsetY: event.clientY - rowRect.top,
      startX: event.clientX,
      startY: event.clientY,
    });
  }

  @action
  startSidebarSectionPointerDrag(section, event) {
    if (
      !this.editingSidebar ||
      !this.workspaceCategory ||
      !section.editable
    ) {
      return;
    }

    if (event.pointerType === "mouse" && event.button !== 0) {
      return;
    }

    const sectionElement = event.currentTarget.closest(
      ".workspace-team-sidebar__section"
    );

    if (!sectionElement) {
      return;
    }

    const sectionRect = sectionElement.getBoundingClientRect();
    this.beginPendingSidebarPointerDrag({
      type: "section",
      element: sectionElement,
      sourceElement: event.currentTarget,
      pointerId: event.pointerId,
      pointerType: event.pointerType,
      sectionId: section.id,
      offsetX: event.clientX - sectionRect.left,
      offsetY: event.clientY - sectionRect.top,
      startX: event.clientX,
      startY: event.clientY,
    });
  }

  beginPendingSidebarPointerDrag(drag) {
    this.cancelSidebarPointerDrag();
    this.sidebarPendingPointerDrag = drag;
    if (drag.pointerType === "touch") {
      this.sidebarPendingPointerDragTimer = setTimeout(() => {
        if (this.sidebarPendingPointerDrag === drag) {
          this.activatePendingSidebarPointerDrag({
            clientX: drag.startX,
            clientY: drag.startY,
            preventDefault() {},
          });
        }
      }, SIDEBAR_TOUCH_LONG_PRESS_MS);
    }
    document.addEventListener("pointermove", this.sidebarPointerMoveCallback, {
      passive: false,
    });
    document.addEventListener("pointerup", this.sidebarPointerUpCallback);
    document.addEventListener(
      "pointercancel",
      this.sidebarPointerCancelCallback
    );
    document.addEventListener("touchend", this.sidebarTouchEndCallback);
    document.addEventListener("touchcancel", this.sidebarTouchCancelCallback);
    window.addEventListener("pointerup", this.sidebarPointerUpCallback);
    window.addEventListener("pointercancel", this.sidebarPointerCancelCallback);
    window.addEventListener("touchend", this.sidebarTouchEndCallback);
    window.addEventListener("touchcancel", this.sidebarTouchCancelCallback);
    document.addEventListener("keydown", this.sidebarPointerKeydownCallback);
    window.addEventListener("blur", this.sidebarPointerCancelCallback);
  }

  activatePendingSidebarPointerDrag(event) {
    const drag = this.sidebarPendingPointerDrag;

    if (!drag) {
      return;
    }

    event.preventDefault();
    this.clearPendingSidebarPointerDragTimer();
    try {
      drag.sourceElement.setPointerCapture?.(drag.pointerId);
    } catch {
      // Timer-activated long press can run outside the browser's pointer dispatch.
    }
    this.lockSidebarDragScrolling(drag.element);
    this.sidebarPointerDrag = {
      type: drag.type,
      categoryId: drag.categoryId,
      sectionId: drag.sectionId,
      offsetX: drag.offsetX,
      offsetY: drag.offsetY,
      clientX: event.clientX,
      clientY: event.clientY,
    };
    this.sidebarPendingPointerDrag = null;
    if (drag.type === "section") {
      this.draggedSidebarSectionId = drag.sectionId;
    } else {
      this.draggedCategoryId = Number(drag.categoryId);
    }
    this.sidebarDropTarget = null;
    this.createSidebarDragPreview(drag.element, drag.element.getBoundingClientRect());
    this.updateSidebarPointerDrag(event);
  }

  createSidebarDragPreview(rowElement, rowRect) {
    const preview = rowElement.cloneNode(true);
    preview.classList.add("workspace-team-sidebar__drag-preview");
    preview.style.width = `${rowRect.width}px`;
    preview.style.height = `${rowRect.height}px`;
    document.body.appendChild(preview);
    this.sidebarDragPreviewElement = preview;
  }

  lockSidebarDragScrolling(rowElement) {
    this.sidebarDragScrollElement =
      rowElement.closest(".workspace-groups-chat-channel-panel") ??
      rowElement.closest(".sidebar-sections");
    this.sidebarDragScrollLockElements = [
      document.body,
      this.sidebarDragScrollElement,
    ].filter(Boolean);

    this.sidebarDragScrollLockElements.forEach((element) =>
      element.classList.add("workspace-team-sidebar-scroll-lock")
    );
  }

  unlockSidebarDragScrolling() {
    this.sidebarDragScrollLockElements?.forEach((element) =>
      element.classList.remove("workspace-team-sidebar-scroll-lock")
    );
    this.sidebarDragScrollLockElements = null;
  }

  updateSidebarPointerDrag(event) {
    if (this.sidebarPendingPointerDrag) {
      this.updatePendingSidebarPointerDrag(event);
      return;
    }

    if (!this.sidebarPointerDrag) {
      return;
    }

    event.preventDefault();
    this.sidebarPointerDrag.clientX = event.clientX;
    this.sidebarPointerDrag.clientY = event.clientY;
    this.moveSidebarDragPreview(event);
    this.sidebarDropTarget = this.dropTargetForPointer(event);
    this.updateSidebarDragAutoScroll();
  }

  updatePendingSidebarPointerDrag(event) {
    const drag = this.sidebarPendingPointerDrag;
    const deltaX = event.clientX - drag.startX;
    const deltaY = event.clientY - drag.startY;
    const distance = Math.hypot(deltaX, deltaY);

    if (distance < SIDEBAR_DRAG_ACTIVATION_PX) {
      return;
    }

    if (
      drag.pointerType === "touch" &&
      Math.abs(deltaY) > Math.abs(deltaX) * SIDEBAR_TOUCH_SCROLL_SLOP_RATIO
    ) {
      this.cancelSidebarPointerDrag();
      return;
    }

    this.activatePendingSidebarPointerDrag(event);
  }

  clearPendingSidebarPointerDragTimer() {
    if (this.sidebarPendingPointerDragTimer) {
      clearTimeout(this.sidebarPendingPointerDragTimer);
      this.sidebarPendingPointerDragTimer = null;
    }
  }

  updateSidebarDragAfterScroll() {
    if (!this.sidebarPointerDrag) {
      return;
    }

    this.moveSidebarDragPreview(this.sidebarPointerDrag);
    this.sidebarDropTarget = this.dropTargetForPointer(this.sidebarPointerDrag);
  }

  updateSidebarDragAutoScroll() {
    const speed = this.sidebarDragAutoScrollSpeed();

    if (speed === 0) {
      this.stopSidebarDragAutoScroll();
      return;
    }

    this.sidebarDragAutoScrollSpeedPx = speed;

    if (!this.sidebarDragAutoScrollFrame) {
      this.sidebarDragAutoScrollFrame = requestAnimationFrame(() =>
        this.runSidebarDragAutoScroll()
      );
    }
  }

  sidebarDragAutoScrollSpeed() {
    const element = this.sidebarDragScrollElement;
    const drag = this.sidebarPointerDrag;

    if (!element || !drag) {
      return 0;
    }

    const rect = element.getBoundingClientRect();
    const edgeSize = Math.min(
      SIDEBAR_DRAG_AUTOSCROLL_EDGE_PX,
      rect.height / 3
    );

    if (drag.clientY < rect.top + edgeSize) {
      const intensity = (rect.top + edgeSize - drag.clientY) / edgeSize;
      return -SIDEBAR_DRAG_AUTOSCROLL_MAX_SPEED_PX * intensity;
    }

    if (drag.clientY > rect.bottom - edgeSize) {
      const intensity = (drag.clientY - (rect.bottom - edgeSize)) / edgeSize;
      return SIDEBAR_DRAG_AUTOSCROLL_MAX_SPEED_PX * intensity;
    }

    return 0;
  }

  runSidebarDragAutoScroll() {
    this.sidebarDragAutoScrollFrame = null;

    const element = this.sidebarDragScrollElement;
    const speed = this.sidebarDragAutoScrollSpeedPx;

    if (!this.sidebarPointerDrag || !element || !speed) {
      return;
    }

    const previousScrollTop = element.scrollTop;
    element.scrollTop += speed;

    if (element.scrollTop !== previousScrollTop) {
      this.updateSidebarDragAfterScroll();
    }

    this.updateSidebarDragAutoScroll();
  }

  stopSidebarDragAutoScroll() {
    if (this.sidebarDragAutoScrollFrame) {
      cancelAnimationFrame(this.sidebarDragAutoScrollFrame);
      this.sidebarDragAutoScrollFrame = null;
    }

    this.sidebarDragAutoScrollSpeedPx = 0;
  }

  dropTargetForPointer(event) {
    const targetElement = document.elementFromPoint(event.clientX, event.clientY);

    if (this.sidebarPointerDrag?.type === "section") {
      const sectionElement = targetElement?.closest?.(
        ".workspace-team-sidebar__section[data-workspace-sidebar-section-id]"
      );

      if (!sectionElement) {
        return null;
      }

      const targetSectionId = sectionElement.dataset.workspaceSidebarSectionId;

      if (
        !targetSectionId ||
        targetSectionId === this.sidebarPointerDrag.sectionId ||
        targetSectionId === OTHER_SECTION_ID
      ) {
        return null;
      }

      const rect = sectionElement.getBoundingClientRect();

      return {
        type: "section",
        sectionId: targetSectionId,
        position: event.clientY < rect.top + rect.height / 2 ? "before" : "after",
      };
    }

    const rowElement = targetElement?.closest?.(
      ".workspace-team-sidebar__row[data-workspace-category-id]"
    );

    if (rowElement) {
      return this.dropTargetForRowElement(rowElement, event.clientY);
    }

    const sectionElement = targetElement?.closest?.(
      "[data-workspace-sidebar-section-id]"
    );

    if (sectionElement) {
      return {
        type: "channel",
        sectionId: sectionElement.dataset.workspaceSidebarSectionId,
        categoryId: null,
        position: "end",
      };
    }

    return null;
  }

  moveSidebarDragPreview(event) {
    const drag = this.sidebarPointerDrag;

    if (!drag || !this.sidebarDragPreviewElement) {
      return;
    }

    this.sidebarDragPreviewElement.style.transform = `translate3d(${
      event.clientX - drag.offsetX
    }px, ${event.clientY - drag.offsetY}px, 0)`;
  }

  dropTargetForRowElement(rowElement, pointerY) {
    const targetCategoryId = Number(rowElement.dataset.workspaceCategoryId);

    if (
      !targetCategoryId ||
      targetCategoryId === Number(this.sidebarPointerDrag?.categoryId)
    ) {
      return null;
    }

    const targetRow = this.rowForCategoryId(targetCategoryId);

    if (!targetRow?.sidebarSectionId) {
      return null;
    }

    const rect = rowElement.getBoundingClientRect();
    return {
      type: "channel",
      sectionId: targetRow.sidebarSectionId,
      categoryId: targetCategoryId,
      position: pointerY < rect.top + rect.height / 2 ? "before" : "after",
    };
  }

  rowForCategoryId(categoryId) {
    for (const group of this.groupedRows) {
      const row = group.rows.find(
        (candidate) => Number(candidate.category.id) === Number(categoryId)
      );

      if (row) {
        return row;
      }
    }

    return null;
  }

  finishSidebarPointerDrag(event) {
    if (this.sidebarPendingPointerDrag && !this.sidebarPointerDrag) {
      this.cancelSidebarPointerDrag();
      return;
    }

    if (!this.sidebarPointerDrag) {
      return;
    }

    event.preventDefault();

    const draggedCategoryId = Number(this.sidebarPointerDrag.categoryId);
    const dropTarget = this.dropTargetForPointer(event) ?? this.sidebarDropTarget;

    if (!dropTarget) {
      this.cancelSidebarPointerDrag();
      return;
    }

    const currentLayout = normalizeSidebarLayout(
      this.sidebarSectionsOverride,
      this.sidebarLayoutOptions
    );

    const nextLayout =
      this.sidebarPointerDrag.type === "section"
        ? moveSidebarSectionInLayout(
            currentLayout,
            this.sidebarPointerDrag.sectionId,
            dropTarget.sectionId,
            dropTarget.position,
            this.sidebarLayoutOptions
          )
        : draggedCategoryId
          ? moveCategoryInSidebarLayout(
              currentLayout,
              draggedCategoryId,
              dropTarget.sectionId,
              dropTarget.categoryId,
              dropTarget.position,
              this.sidebarLayoutOptions
            )
          : null;

    if (!nextLayout) {
      this.cancelSidebarPointerDrag();
      return;
    }

    void this.persistSidebarSections(nextLayout, currentLayout);
    this.cancelSidebarPointerDrag();
  }

  finishSidebarTouchDrag(event) {
    if (!this.sidebarPointerDrag) {
      this.cancelSidebarPointerDrag();
      return;
    }

    const touch = event?.changedTouches?.[0];
    const drag = this.sidebarPointerDrag;
    this.finishSidebarPointerDrag({
      clientX: touch?.clientX ?? drag.clientX,
      clientY: touch?.clientY ?? drag.clientY,
      preventDefault() {
        event?.preventDefault?.();
      },
    });
  }

  cancelSidebarPointerDrag() {
    document.removeEventListener("pointermove", this.sidebarPointerMoveCallback);
    document.removeEventListener("pointerup", this.sidebarPointerUpCallback);
    document.removeEventListener(
      "pointercancel",
      this.sidebarPointerCancelCallback
    );
    document.removeEventListener("touchend", this.sidebarTouchEndCallback);
    document.removeEventListener("touchcancel", this.sidebarTouchCancelCallback);
    window.removeEventListener("pointerup", this.sidebarPointerUpCallback);
    window.removeEventListener(
      "pointercancel",
      this.sidebarPointerCancelCallback
    );
    window.removeEventListener("touchend", this.sidebarTouchEndCallback);
    window.removeEventListener("touchcancel", this.sidebarTouchCancelCallback);
    document.removeEventListener("keydown", this.sidebarPointerKeydownCallback);
    window.removeEventListener("blur", this.sidebarPointerCancelCallback);
    this.stopSidebarDragAutoScroll();
    this.unlockSidebarDragScrolling();
    this.sidebarDragPreviewElement?.remove();
    this.sidebarDragPreviewElement = null;
    this.clearPendingSidebarPointerDragTimer();
    this.sidebarPendingPointerDrag = null;
    this.sidebarPointerDrag = null;
    this.sidebarDragScrollElement = null;
    this.draggedCategoryId = null;
    this.draggedSidebarSectionId = null;
    this.sidebarDropTarget = null;
  }

  applyEditingSidebarSectionTitle({ persist = false } = {}) {
    if (!this.editingSidebarSectionId) {
      return null;
    }

    const title = this.editingSidebarSectionTitle.trim();

    if (!title) {
      return null;
    }

    const currentLayout = normalizeSidebarLayout(
      this.sidebarSectionsOverride,
      this.sidebarLayoutOptions
    );
    const nextLayout = renameSidebarSection(
      currentLayout,
      this.editingSidebarSectionId,
      title,
      this.sidebarLayoutOptions
    );

    if (!nextLayout) {
      return null;
    }

    this.applySidebarSectionsLocally(nextLayout);
    this.cancelSidebarSectionTitleEdit();
    if (persist) {
      void this.persistSidebarSections(nextLayout, currentLayout);
    }
    return nextLayout;
  }

  @action
  addSidebarSection() {
    if (!this.editingSidebar) {
      return;
    }

    this.applyEditingSidebarSectionTitle();

    const currentLayout = normalizeSidebarLayout(
      this.sidebarSectionsOverride,
      this.sidebarLayoutOptions
    );
    const sectionId = uniqueSidebarSectionId(currentLayout);
    const title = i18n("discourse_workspace_groups.new_channel_group");
    const nextLayout = insertSidebarSection(
      currentLayout,
      { id: sectionId, title },
      0,
      this.sidebarLayoutOptions
    );

    this.applySidebarSectionsLocally(nextLayout);
    this.editingSidebarSectionId = sectionId;
    this.editingSidebarSectionTitle = title;
    this.rememberWorkspaceSidebarEditingState({
      editing: true,
      sectionId,
      title,
      layout: nextLayout,
    });
    void this.persistSidebarSections(nextLayout, currentLayout);
  }

  @action
  editSidebarSectionTitle(section) {
    if (!this.editingSidebar || !section.editable) {
      return;
    }

    this.editingSidebarSectionId = section.id;
    this.editingSidebarSectionTitle = section.title;
    this.rememberWorkspaceSidebarEditingState({
      editing: true,
      sectionId: section.id,
      title: section.title,
    });
  }

  @action
  updateSidebarSectionTitle(event) {
    this.editingSidebarSectionTitle = event.target.value;
    this.rememberWorkspaceSidebarEditingState({
      editing: true,
      title: this.editingSidebarSectionTitle,
    });
  }

  @action
  handleSidebarSectionTitleKeydown(section, event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.saveSidebarSectionTitle(section);
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.cancelSidebarSectionTitleEdit();
    }
  }

  @action
  focusSidebarSectionTitleInput(element) {
    if (this.site.mobileView) {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          if (!element.isConnected) {
            return;
          }

          element.scrollIntoView({ block: "nearest" });
          element.focus({ preventScroll: true });
          element.select();
        });
      });
      return;
    }

    element.focus();
    element.select();
  }

  @action
  saveSidebarSectionTitle(section) {
    if (
      !this.editingSidebar ||
      !section.editable ||
      this.sidebarSectionTitleInvalid
    ) {
      return;
    }

    this.applyEditingSidebarSectionTitle({ persist: true });
  }

  @action
  cancelSidebarSectionTitleEdit() {
    this.editingSidebarSectionId = null;
    this.editingSidebarSectionTitle = "";
    if (this.editingSidebar) {
      this.rememberWorkspaceSidebarEditingState({
        editing: true,
        sectionId: null,
        title: "",
      });
    }
  }

  @action
  async deleteSidebarSection(section) {
    if (!this.editingSidebar || !section.editable) {
      return;
    }

    if (section.rows.length > 0) {
      const confirmed = await this.dialog.confirm({
        message: i18n(
          "discourse_workspace_groups.delete_channel_group_message",
          { group_name: section.title }
        ),
        confirmButtonLabel:
          "discourse_workspace_groups.delete_channel_group_confirm",
        cancelButtonLabel: "cancel",
      });

      if (!confirmed) {
        return;
      }
    }

    const currentLayout = normalizeSidebarLayout(
      this.sidebarSectionsOverride,
      this.sidebarLayoutOptions
    );
    const nextLayout = deleteSidebarSectionFromLayout(
      currentLayout,
      section.id,
      this.sidebarLayoutOptions
    );

    if (!nextLayout) {
      return;
    }

    if (this.editingSidebarSectionId === section.id) {
      this.cancelSidebarSectionTitleEdit();
    }

    this.applySidebarSectionsLocally(nextLayout);
    void this.persistSidebarSections(nextLayout, currentLayout);
  }

  @action
  async toggleSidebarSection(section) {
    const currentLayout = normalizeSidebarLayout(
      this.currentSidebarLayout,
      this.sidebarLayoutOptions
    );
    const nextLayout = toggleSidebarSectionCollapsed(
      currentLayout,
      section.id,
      this.sidebarLayoutOptions
    );

    if (this.editingSidebar) {
      void this.persistSidebarSections(nextLayout, currentLayout);
      return;
    }

    await this.persistSidebarSections(nextLayout, currentLayout);
  }

  <template>
    <div
      {{didInsert this.initializeSidebar}}
      data-section-name={{this.sectionName}}
      class={{dConcatClass
        "sidebar-section"
        "sidebar-section-wrapper"
        "workspace-team-sidebar"
        (if this.draggingSidebarItem "workspace-team-sidebar--dragging")
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
            {{dIcon this.headerCaretIcon}}
          </span>

          <span class="sidebar-section-header-text">
            {{this.headerText}}
          </span>
        </SectionHeader>

        {{#if this.inWorkspaceContext}}
          <div class="workspace-team-sidebar__header-actions">
            {{#if this.canEditSidebar}}
              {{#unless this.editingSidebar}}
                <button
                  type="button"
                  title={{this.sidebarEditTitle}}
                  aria-label={{this.sidebarEditTitle}}
                  class="workspace-team-sidebar__header-action-button"
                  {{on "click" this.toggleSidebarEditing}}
                >
                  {{dIcon "pencil"}}
                </button>
              {{/unless}}
            {{/if}}

            <div class="workspace-team-sidebar__header-switcher">
              <button
                type="button"
                title={{this.switchWorkspaceTitle}}
                aria-label={{this.switchWorkspaceTitle}}
                aria-haspopup="menu"
                aria-expanded={{if this.headerActionsMenuOpen "true" "false"}}
                class="workspace-team-sidebar__header-action-button"
                {{on "click" this.toggleHeaderActionsMenu}}
              >
                {{dIcon this.headerActionsIcon}}
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
          </div>
        {{/if}}
      </div>

      {{#if this.inWorkspaceContext}}
        <div class="workspace-team-sidebar__controls">
          {{#if this.editingSidebar}}
            {{#if this.canEditSidebar}}
              <button
                type="button"
                title={{this.addChannelGroupTitle}}
                aria-label={{this.addChannelGroupTitle}}
                class="workspace-team-sidebar__control"
                {{on "click" this.addSidebarSection}}
              >
                {{dIcon "plus"}}
                <span>{{this.addChannelGroupLabel}}</span>
              </button>

              <button
                type="button"
                title={{this.sidebarEditTitle}}
                aria-label={{this.sidebarEditTitle}}
                class="workspace-team-sidebar__control workspace-team-sidebar__control--primary"
                {{on "click" this.toggleSidebarEditing}}
              >
                {{dIcon "check"}}
                <span>{{this.sidebarEditLabel}}</span>
              </button>
            {{/if}}
          {{else}}
            <button
              type="button"
              title={{this.overviewTitle}}
              aria-label={{this.overviewTitle}}
              class="workspace-team-sidebar__control"
              {{on "click" this.openOverview}}
            >
              {{dIcon "layer-group"}}
              <span>{{this.overviewLabel}}</span>
            </button>

            <button
              type="button"
              title={{this.unreadFilterTitle}}
              aria-label={{this.unreadFilterTitle}}
              aria-pressed={{if this.showUnreadOnly "true" "false"}}
              class={{dConcatClass
                "workspace-team-sidebar__control"
                (if
                  this.showUnreadOnly
                  "workspace-team-sidebar__control--active"
                )
              }}
              {{on "click" this.toggleUnreadFilter}}
            >
              {{dIcon "filter"}}
              <span>{{this.unreadLabel}}</span>
            </button>

            {{#if this.canOpenChannelFinder}}
              <button
                type="button"
                title={{this.channelFinderTitle}}
                aria-label={{this.channelFinderTitle}}
                class="workspace-team-sidebar__control workspace-team-sidebar__control--icon-only"
                {{on "click" this.openChannelFinder}}
              >
                {{dIcon "magnifying-glass"}}
              </button>
            {{/if}}
          {{/if}}
        </div>
      {{/if}}

      {{#if this.displaySectionContent}}
        {{#if this.showWorkspaceNavigationHint}}
          <div class="workspace-team-sidebar__hint">
            <p>
              {{this.workspaceNavigationHint}}
            </p>
            <button
              type="button"
              class="workspace-team-sidebar__hint-dismiss"
              {{on "click" this.dismissWorkspaceNavigationHint}}
            >
              {{this.dismissWorkspaceNavigationHintLabel}}
            </button>
          </div>
        {{/if}}

        <ul
          id={{this.sidebarSectionContentId}}
          class="sidebar-section-content"
        >
          {{#if this.inWorkspaceContext}}
            {{#if this.editingSidebar}}
              {{#each this.editableGroups as |group|}}
                {{#if group.title}}
                  <li
                    class={{dConcatClass
                      "workspace-team-sidebar__section"
                      (if
                        group.draggingSection
                        "workspace-team-sidebar__section--dragging"
                      )
                      (if
                        group.dropTarget
                        "workspace-team-sidebar__section--drop-target"
                      )
                      (if
                        group.sectionDropBefore
                        "workspace-team-sidebar__section--drop-before"
                      )
                      (if
                        group.sectionDropAfter
                        "workspace-team-sidebar__section--drop-after"
                      )
                    }}
                    data-workspace-sidebar-section-id={{group.id}}
                  >
                    {{#if group.editingTitle}}
                      <input
                        type="text"
                        value={{this.editingSidebarSectionTitle}}
                        class="workspace-team-sidebar__section-title-input"
                        aria-label={{this.groupNameLabel}}
                        {{didInsert this.focusSidebarSectionTitleInput}}
                        {{on "input" this.updateSidebarSectionTitle}}
                        {{on
                          "keydown"
                          (fn this.handleSidebarSectionTitleKeydown group)
                        }}
                      />
                      <button
                        type="button"
                        title={{this.saveGroupNameLabel}}
                        aria-label={{this.saveGroupNameLabel}}
                        class="workspace-team-sidebar__section-action"
                        disabled={{this.sidebarSectionTitleInvalid}}
                        {{on "click" (fn this.saveSidebarSectionTitle group)}}
                      >
                        {{dIcon "check"}}
                      </button>
                      <button
                        type="button"
                        title={{this.cancelGroupRenameLabel}}
                        aria-label={{this.cancelGroupRenameLabel}}
                        class="workspace-team-sidebar__section-action"
                        {{on "click" this.cancelSidebarSectionTitleEdit}}
                      >
                        {{dIcon "xmark"}}
                      </button>
                    {{else}}
                      <button
                        type="button"
                        class={{dConcatClass
                          "workspace-team-sidebar__section-heading"
                          (if
                            group.unread
                            "workspace-team-sidebar__section-heading--unread"
                          )
                        }}
                        {{! eslint-disable-next-line ember/template-no-pointer-down-event-binding }}
                        {{on
                          "pointerdown"
                          (fn this.startSidebarSectionPointerDrag group)
                        }}
                        {{on "click" (fn this.toggleSidebarSection group)}}
                      >
                        {{dIcon
                          (if group.collapsed "angle-right" "angle-down")
                        }}
                        <span>{{group.title}}</span>
                        {{#if group.unread}}
                          <span class="chat-channel-unread-indicator"></span>
                        {{/if}}
                      </button>

                      {{#if group.editable}}
                        <button
                          type="button"
                          title={{this.renameGroupLabel}}
                          aria-label={{this.renameGroupLabel}}
                          class="workspace-team-sidebar__section-action"
                          {{on
                            "click"
                            (fn this.editSidebarSectionTitle group)
                          }}
                        >
                          {{dIcon "pencil"}}
                        </button>
                        <button
                          type="button"
                          title={{this.deleteGroupLabel}}
                          aria-label={{this.deleteGroupLabel}}
                          class="workspace-team-sidebar__section-action"
                          {{on "click" (fn this.deleteSidebarSection group)}}
                        >
                          {{dIcon "trash-can"}}
                        </button>
                      {{/if}}
                    {{/if}}
                  </li>
                {{/if}}

                {{#unless group.collapsed}}
                  {{#unless group.rows.length}}
                    <li
                      class={{dConcatClass
                        "workspace-team-sidebar__section-drop-target"
                        "workspace-team-sidebar__section-drop-target--empty"
                        (if
                          group.dropTarget
                          "workspace-team-sidebar__section-drop-target--active"
                        )
                      }}
                      data-workspace-sidebar-section-id={{group.id}}
                    >
                      {{dIcon "grip-lines"}}
                      <span>{{this.dragChannelsHereLabel}}</span>
                    </li>
                  {{/unless}}

                  {{#each group.rows as |row|}}
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
                      @dropBefore={{row.dropBefore}}
                      @dropAfter={{row.dropAfter}}
                      @startPointerDrag={{fn this.startSidebarPointerDrag row}}
                    />
                  {{/each}}

                  {{#if group.rows.length}}
                    <li
                      class={{dConcatClass
                        "workspace-team-sidebar__section-drop-target"
                        "workspace-team-sidebar__section-drop-target--tail"
                        (if
                          group.dropTarget
                          "workspace-team-sidebar__section-drop-target--active"
                        )
                      }}
                      data-workspace-sidebar-section-id={{group.id}}
                    ></li>
                  {{/if}}
                {{/unless}}
              {{else}}
                <li class="workspace-team-sidebar__empty">
                  {{this.noChannelsLabel}}
                </li>
              {{/each}}
            {{else}}
              {{#each this.groupedRows as |group|}}
                {{#if group.title}}
                  <li
                    class="workspace-team-sidebar__section"
                  >
                    <button
                      type="button"
                      class={{dConcatClass
                        "workspace-team-sidebar__section-heading"
                        (if
                          group.unread
                          "workspace-team-sidebar__section-heading--unread"
                        )
                      }}
                      {{on "click" (fn this.toggleSidebarSection group)}}
                    >
                      {{dIcon (if group.collapsed "angle-right" "angle-down")}}
                      <span>{{group.title}}</span>
                      {{#if group.unread}}
                        <span class="chat-channel-unread-indicator"></span>
                      {{/if}}
                    </button>
                  </li>
                {{/if}}

                {{#unless group.collapsed}}
                  {{#each group.rows as |row|}}
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
                    />
                  {{/each}}
                {{/unless}}
              {{else}}
                <li class="workspace-team-sidebar__empty">
                  {{this.noUnreadChannelsLabel}}
                </li>
              {{/each}}
            {{/if}}
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
                    {{dIcon "users"}}
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
