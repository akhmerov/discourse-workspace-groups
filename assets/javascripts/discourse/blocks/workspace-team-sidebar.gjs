import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
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
  @tracked editingSidebar = false;
  @tracked orderedChannelIds = null;
  @tracked savingSidebarOrder = false;

  sectionName = "workspace-team";
  sidebarSectionContentId = getSidebarSectionContentId(this.sectionName);
  collapsedSidebarSectionKey = getCollapsedSidebarSectionKey(this.sectionName);

  constructor() {
    super(...arguments);

    this.linkCache = new Map();
    this.topicTrackingCallbackId = this.topicTrackingState.onStateChange(() => {
      this.topicCountsVersion++;
      this.rows.forEach((row) => row.categoryLink.refreshCounts());
    });
  }

  willDestroy() {
    super.willDestroy(...arguments);

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
      const categoryAvailable = workspaceCategoryModeEnabled(category);
      const chatAvailable = workspaceChatModeEnabled(category) && !!pairedChannel;
      const chatMuted = !!pairedChannel?.currentUserMembership?.muted;

      return {
        category,
        categoryLink,
        categoryUnread:
          categoryAvailable && !chatMuted && !!categoryLink.activeCountable,
        categoryTitle: `Open ${category.displayName} topics`,
        chatPath: pairedChannel
          ? `/chat/c/${pairedChannel.routeModels.join("/")}`
          : null,
        chatTitle: `Open ${category.displayName} chat`,
        chatUnread: chatAvailable && !chatMuted && !!(
          pairedChannel &&
          (pairedChannel.tracking.unreadCount > 0 ||
            pairedChannel.unreadThreadsCountSinceLastViewed > 0 ||
            pairedChannel.tracking.mentionCount > 0 ||
            pairedChannel.tracking.watchedThreadsUnreadCount > 0)
        ),
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

    memberWorkspaceCategories(this.services)
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
    return this.workspaceCategory?.displayName ?? "team";
  }

  get overviewTitle() {
    return this.workspaceCategory
      ? `Open ${this.workspaceCategory.displayName} overview`
      : null;
  }

  get canEditSidebar() {
    return !!this.workspaceCategory && this.rows.length > 1;
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

  @action
  initializeExpandedState() {
    if (this.sidebarState.filter) {
      return;
    }

    if (this.isCollapsed) {
      this.sidebarState.collapseSection(this.sectionName);
    } else {
      this.sidebarState.expandSection(this.sectionName);
    }
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
  handleWorkspaceSelection(id) {
    this.headerActions.find((headerAction) => headerAction.id === id)?.action();
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
      {{didInsert this.initializeExpandedState}}
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

        {{#if this.canEditSidebar}}
          <button
            type="button"
            title={{this.sidebarEditTitle}}
            aria-label={{this.sidebarEditTitle}}
            class="sidebar-section-header-button workspace-team-sidebar__edit-button btn-icon btn-flat"
            disabled={{this.savingSidebarOrder}}
            {{on "click" this.toggleSidebarEditing}}
          >
            {{icon (if this.editingSidebar "check" "pencil")}}
          </button>
        {{/if}}

        {{#if this.headerActions.length}}
          <DropdownSelectBox
            @options={{hash
              icon=this.headerActionsIcon
              placementStrategy="absolute"
            }}
            @content={{this.headerActions}}
            @onChange={{this.handleWorkspaceSelection}}
            class="sidebar-section-header-dropdown workspace-team-sidebar__switcher"
          />
        {{/if}}

        {{#if this.workspaceCategory}}
          <button
            type="button"
            title={{this.overviewTitle}}
            class="sidebar-section-header-button workspace-team-sidebar__overview-button btn-icon btn-flat"
            {{on "click" this.openOverview}}
          >
            {{icon "layer-group"}}
          </button>
        {{/if}}
      </div>

      {{#if this.displaySectionContent}}
        <ul
          id={{this.sidebarSectionContentId}}
          class="sidebar-section-content"
        >
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
        </ul>
      {{/if}}
    </div>
  </template>
}
