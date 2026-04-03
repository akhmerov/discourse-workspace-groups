import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import { action } from "@ember/object";
import { service } from "@ember/service";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import SectionLinkPrefix from "discourse/components/sidebar/section-link-prefix";
import DiscourseURL from "discourse/lib/url";

export default class WorkspaceTeamSidebarRow extends Component {
  @service("chat-state-manager") chatStateManager;

  get categoryModels() {
    if (this.args.categoryLink.model) {
      return [this.args.categoryLink.model];
    }

    return this.args.categoryLink.models ?? [];
  }

  get categoryQuery() {
    return this.args.categoryLink.query ?? {};
  }

  get categoryButtonClass() {
    return concatClass(
      "workspace-team-sidebar__mode-button",
      this.args.categoryActive && "workspace-team-sidebar__mode-button--active"
    );
  }

  get chatButtonClass() {
    return concatClass(
      "workspace-team-sidebar__mode-button",
      this.args.chatActive && "workspace-team-sidebar__mode-button--active"
    );
  }

  get chatDisabled() {
    return !this.args.chatPath;
  }

  @action
  openChat(event) {
    if (!this.args.chatPath) {
      event.preventDefault();
      return;
    }

    event.preventDefault();
    this.chatStateManager?.prefersFullPage();
    DiscourseURL.routeTo(this.args.chatPath);
  }

  <template>
    <li
      class="sidebar-section-link-wrapper"
      data-list-item-name={{@categoryLink.name}}
    >
      <div
        class={{concatClass
          "workspace-team-sidebar__row"
          "sidebar-row"
          @isActive
          "workspace-team-sidebar__row--active"
        }}
      >
        <LinkTo
          @route={{@categoryLink.route}}
          @models={{this.categoryModels}}
          @query={{this.categoryQuery}}
          @current-when={{@categoryLink.currentWhen}}
          @title={{@categoryLink.title}}
          class={{concatClass
            "workspace-team-sidebar__main-link"
            "sidebar-section-link"
            @isActive
            "active"
          }}
        >
          <SectionLinkPrefix
            @prefixType={{@categoryLink.prefixType}}
            @prefixValue={{@categoryLink.prefixValue}}
            @prefixColor={{@categoryLink.prefixColor}}
            @prefixBadge={{@categoryLink.prefixBadge}}
          />

          <span class="sidebar-section-link-content-text">
            {{@categoryLink.text}}
          </span>

          {{#if @categoryLink.badgeText}}
            <span class="sidebar-section-link-content-badge">
              {{@categoryLink.badgeText}}
            </span>
          {{/if}}
        </LinkTo>

        <div class="workspace-team-sidebar__modes">
          <LinkTo
            @route={{@categoryLink.route}}
            @models={{this.categoryModels}}
            @query={{this.categoryQuery}}
            @current-when={{@categoryLink.currentWhen}}
            @title={{@categoryTitle}}
            class={{this.categoryButtonClass}}
          >
            <span class="workspace-team-sidebar__mode-icon">
              {{icon "list"}}

              {{#if @categoryUnread}}
                <span class="chat-channel-unread-indicator"></span>
              {{/if}}
            </span>
          </LinkTo>

          <button
            type="button"
            class={{this.chatButtonClass}}
            title={{@chatTitle}}
            aria-label={{@chatTitle}}
            disabled={{this.chatDisabled}}
            {{on "click" this.openChat}}
          >
            <span class="workspace-team-sidebar__mode-icon">
              {{icon "d-chat"}}

              {{#if @chatUnread}}
                <span class="chat-channel-unread-indicator"></span>
              {{/if}}
            </span>
          </button>
        </div>
      </div>
    </li>
  </template>
}
