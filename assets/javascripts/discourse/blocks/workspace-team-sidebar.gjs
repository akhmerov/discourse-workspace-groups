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
  workspaceCategoryModeEnabled,
  workspaceChatModeEnabled,
  workspaceOverviewPath,
} from "../lib/workspace-team-sidebar-state";

const WORKSPACE_FOCUS_KEY = "workspace-groups:focused-workspace-id";
const WORKSPACE_NAV_HINT_KEY = "workspace-groups:navigation-hint-seen";

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
  @tracked editingSidebar = false;
  @tracked orderedChannelIds = null;
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

  get rows() {
    this.topicCountsVersion;
    this.chatHydrationVersion;
    this.ensureWorkspaceChatChannels();

    const categories =
      sidebarChannelCategories(this.services, this.orderedChannelIds) ?? [];
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
    return "right-left";
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
  runHeaderAction(headerAction) {
    headerAction.action();
  }

  @action
  dismissWorkspaceNavigationHint() {
    this.markWorkspaceNavigationHintSeen();
  }

  @action
  toggleSidebarEditing() {
    if (!this.canEditSidebar) {
      return;
    }

    this.showUnreadOnly = false;

    if (this.editingSidebar) {
      this.editingSidebar = false;
      this.orderedChannelIds = null;
      return;
    }

    this.editingSidebar = true;
    this.orderedChannelIds = this.rows.map((row) => row.category.id);
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
  async reorderSidebarRows(targetCategory, above) {
    if (!this.editingSidebar || this.savingSidebarOrder || !this.workspaceCategory) {
      return;
    }

    const currentOrder = [...(this.orderedChannelIds ?? this.rows.map((row) => row.category.id))];
    const draggedCategoryId = this.draggedCategoryId;

    if (!draggedCategoryId || draggedCategoryId === targetCategory.id) {
      return;
    }

    const nextOrder = currentOrder.filter((categoryId) => categoryId !== draggedCategoryId);
    const targetIndex = nextOrder.indexOf(targetCategory.id);
    const insertIndex = above ? targetIndex : targetIndex + 1;
    nextOrder.splice(insertIndex, 0, draggedCategoryId);

    this.orderedChannelIds = nextOrder;
    this.savingSidebarOrder = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.workspaceCategory.id}/sidebar-channels`,
        {
          type: "PUT",
          data: { channel_ids: nextOrder },
        }
      );

      this.orderedChannelIds = result.channel_ids;
      this.updateCurrentUserSidebarOrders(
        this.workspaceCategory.id,
        result.channel_ids
      );
    } catch (error) {
      this.orderedChannelIds = currentOrder;
      popupAjaxError(error);
    } finally {
      this.savingSidebarOrder = false;
    }
  }

  @action
  setDraggedCategory(category) {
    this.draggedCategoryId = category?.id ?? null;
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
          <details class="workspace-team-sidebar__header-switcher">
            <summary
              title="Switch workspace"
              aria-label="Switch workspace"
              class="workspace-team-sidebar__header-switcher-button"
            >
              {{icon this.headerActionsIcon}}
            </summary>
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
          </details>
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
            {{#each this.filteredRows as |row|}}
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
                @setDraggedCategory={{this.setDraggedCategory}}
                @reorderCallback={{this.reorderSidebarRows}}
                @dragDisabled={{this.savingSidebarOrder}}
              />
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
