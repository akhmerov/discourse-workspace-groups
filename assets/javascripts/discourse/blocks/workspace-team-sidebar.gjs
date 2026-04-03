import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { service } from "@ember/service";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { block } from "discourse/blocks";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import SectionHeader from "discourse/components/sidebar/section-header";
import CategorySectionLink from "discourse/lib/sidebar/user/categories-section/category-section-link";
import {
  getCollapsedSidebarSectionKey,
  getSidebarSectionContentId,
} from "discourse/lib/sidebar/helpers";
import DiscourseURL from "discourse/lib/url";
import DropdownSelectBox from "discourse/select-kit/components/dropdown-select-box";
import {
  currentScopedCategory,
  currentScopedMode,
  pairedCategoryChannelFor,
  sidebarChannelCategories,
  sidebarWorkspaceCategory,
  visibleWorkspaceCategories,
  workspaceOverviewPath,
} from "../lib/workspace-team-sidebar-state";
import WorkspaceTeamSidebarRow from "../components/workspace-team-sidebar-row";

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

  get rows() {
    this.topicCountsVersion;

    const categories = sidebarChannelCategories(this.services) ?? [];
    const categoryIds = new Set(categories.map((category) => category.id));

    for (const linkId of this.linkCache.keys()) {
      if (!categoryIds.has(linkId)) {
        this.linkCache.delete(linkId);
      }
    }

    return categories.map((category) => {
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

      const categoryLink = this.linkCache.get(category.id);
      const pairedChannel = pairedCategoryChannelFor(
        category,
        this.chatChannelsManager
      );

      return {
        category,
        categoryLink,
        categoryUnread: !!categoryLink.activeCountable,
        categoryTitle: `Open ${category.displayName} topics`,
        chatPath: pairedChannel
          ? `/chat/c/${pairedChannel.routeModels.join("/")}`
          : null,
        chatTitle: `Open ${category.displayName} chat`,
        chatUnread: !!(
          pairedChannel &&
          (pairedChannel.tracking.unreadCount > 0 ||
            pairedChannel.unreadThreadsCountSinceLastViewed > 0 ||
            pairedChannel.tracking.mentionCount > 0 ||
            pairedChannel.tracking.watchedThreadsUnreadCount > 0)
        ),
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

    visibleWorkspaceCategories(this.services)
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

        {{#if this.workspaceCategory}}
          <button
            type="button"
            title={{this.overviewTitle}}
            class="sidebar-section-header-button workspace-team-sidebar__overview-button btn-icon btn-flat"
            {{on "click" this.openOverview}}
          >
            {{icon "table-cells-large"}}
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
          @isActive={{row.isActive}}
          @categoryActive={{row.categoryActive}}
          @chatActive={{row.chatActive}}
        />
      {{/each}}
        </ul>
      {{/if}}
    </div>
  </template>
}
