import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
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
import DropdownSelectBox from "discourse/select-kit/components/dropdown-select-box";
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

  sectionName = "workspace-team";
  sidebarSectionContentId = getSidebarSectionContentId(this.sectionName);
  collapsedSidebarSectionKey = getCollapsedSidebarSectionKey(this.sectionName);
  focusedSidebarClass = "workspace-team-sidebar--focused";

  constructor() {
    super(...arguments);

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

  get workspaceCategory() {
    return sidebarWorkspaceCategory(this.services);
  }

  get memberWorkspaces() {
    return memberWorkspaceCategories(this.services);
  }

  get inWorkspaceContext() {
    if (currentWorkspaceCategory(this.services)) {
      return true;
    }

    const overviewPath = workspaceOverviewPath(this.workspaceCategory);
    return !!(
      overviewPath && this.router.currentURL?.startsWith(overviewPath)
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
      const chatUnread =
        chatAvailable && !chatMuted && chatChannelHasUnread(pairedChannel);
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
          action: () => DiscourseURL.routeTo(workspaceOverviewPath(workspace)),
        })
      );

    return actions;
  }

  get headerActionsIcon() {
    return "users";
  }

  get headerText() {
    return this.inWorkspaceContext
      ? (this.workspaceCategory?.displayName ?? "team")
      : "teams";
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

  get leaveWorkspaceTitle() {
    return "Leave workspace";
  }

  workspaceTitle(workspace) {
    return `Open ${workspace.displayName} workspace`;
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
    this.sidebarSectionsElement?.classList.toggle(
      this.focusedSidebarClass,
      this.inWorkspaceContext
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

    DiscourseURL.routeTo(workspaceOverviewPath(this.workspaceCategory));
  }

  @action
  leaveWorkspace() {
    DiscourseURL.routeTo("/latest");
  }

  @action
  handleWorkspaceSelection(id) {
    this.headerActions.find((headerAction) => headerAction.id === id)?.action();
  }

  @action
  openWorkspace(workspace) {
    DiscourseURL.routeTo(workspaceOverviewPath(workspace));
  }

  @action
  toggleSidebarEditing() {
    if (!this.canEditSidebar) {
      return;
    }

    if (this.editingSidebar) {
      this.editingSidebar = false;
      this.orderedChannelIds = null;
      return;
    }

    this.editingSidebar = true;
    this.orderedChannelIds = this.rows.map((row) => row.category.id);
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
          {{#if this.headerActions.length}}
            <DropdownSelectBox
              @options={{hash
                icon=this.headerActionsIcon
                placementStrategy="absolute"
              }}
              @content={{this.headerActions}}
              @onChange={{this.handleWorkspaceSelection}}
              class="sidebar-section-header-dropdown workspace-team-sidebar__header-switcher"
            />
          {{/if}}
        {{/if}}
      </div>

      {{#if this.inWorkspaceContext}}
        <div class="workspace-team-sidebar__controls">
          <button
            type="button"
            title={{this.leaveWorkspaceTitle}}
            aria-label={{this.leaveWorkspaceTitle}}
            class="workspace-team-sidebar__control"
            {{on "click" this.leaveWorkspace}}
          >
            {{icon "arrow-left"}}
            <span>Forum</span>
          </button>

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
        <ul
          id={{this.sidebarSectionContentId}}
          class="sidebar-section-content"
        >
          {{#if this.inWorkspaceContext}}
            {{#each this.rows as |row|}}
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
