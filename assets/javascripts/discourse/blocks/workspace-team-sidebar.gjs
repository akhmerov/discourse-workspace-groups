import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { getOwner } from "@ember/owner";
import { service } from "@ember/service";
import { block } from "discourse/blocks";
import Section from "discourse/components/sidebar/section";
import CategorySectionLink from "discourse/lib/sidebar/user/categories-section/category-section-link";
import DiscourseURL from "discourse/lib/url";
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
  @service router;
  @service site;
  @service("site-settings") siteSettings;
  @service("topic-tracking-state") topicTrackingState;

  @tracked topicCountsVersion = 0;

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

    const actions = [
      {
        id: "open-overview",
        title: `Open ${this.workspaceCategory.displayName} overview`,
        action: () =>
          DiscourseURL.routeTo(workspaceOverviewPath(this.workspaceCategory)),
      },
    ];

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
    return this.headerActions.length > 1 ? "users" : "info-circle";
  }

  get headerText() {
    return this.workspaceCategory?.displayName ?? "team";
  }

  <template>
    <Section
      @sectionName="workspace-team"
      @headerLinkText={{this.headerText}}
      @headerActions={{this.headerActions}}
      @headerActionsIcon={{this.headerActionsIcon}}
      @collapsable={{true}}
      @displaySection={{true}}
      @collapsedByDefault={{false}}
      class="workspace-team-sidebar"
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
    </Section>
  </template>
}
