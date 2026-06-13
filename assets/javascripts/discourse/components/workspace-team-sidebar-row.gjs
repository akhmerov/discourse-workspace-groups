import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { isHex } from "discourse/components/sidebar/section-link";
import SectionLinkPrefix from "discourse/components/sidebar/section-link-prefix";
import DiscourseURL from "discourse/lib/url";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";

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

  get categoryAvailable() {
    return this.args.categoryAvailable !== false;
  }

  get chatAvailable() {
    return this.args.chatAvailable !== false;
  }

  get prefixColor() {
    const hexCode = isHex(this.args.categoryLink.prefixColor);
    return hexCode ? `#${hexCode}` : this.args.categoryLink.prefixColor;
  }

  get prefixBadge() {
    if (
      this.args.categoryLink.category?.workspace_visibility === "public" &&
      this.args.categoryLink.prefixBadge
    ) {
      return null;
    }

    return this.args.categoryLink.prefixBadge;
  }

  get categoryButtonClass() {
    return dConcatClass(
      "workspace-team-sidebar__mode-button",
      this.args.chatMuted && "workspace-team-sidebar__mode-button--muted",
      this.args.categoryActive && "workspace-team-sidebar__mode-button--active"
    );
  }

  get chatButtonClass() {
    return dConcatClass(
      "workspace-team-sidebar__mode-button",
      this.args.chatMuted && "workspace-team-sidebar__mode-button--muted",
      this.args.chatActive && "workspace-team-sidebar__mode-button--active"
    );
  }

  get chatDisabled() {
    return !this.args.chatPath;
  }

  get mainLinkOpensChat() {
    return !this.categoryAvailable && !!this.args.chatPath;
  }

  get showModes() {
    return this.categoryAvailable && this.chatAvailable;
  }

  get mainLinkClass() {
    return dConcatClass(
      "workspace-team-sidebar__main-link",
      "sidebar-section-link",
      this.args.chatMuted && "sidebar-section-link--muted",
      this.args.editable && "workspace-team-sidebar__main-link--editing",
      !this.showModes &&
        !this.args.editable &&
        "workspace-team-sidebar__main-link--compact",
      this.mainLinkUnread && "workspace-team-sidebar__main-link--unread",
      this.mainLinkActive && "active"
    );
  }

  get mainLinkActive() {
    if (this.mainLinkOpensChat) {
      return this.args.chatActive;
    }

    return this.args.categoryActive;
  }

  get mainLinkUnread() {
    return !!(this.args.categoryUnread || this.args.chatUnread);
  }

  get mainLinkUnreadIndicatorClass() {
    return "chat-channel-unread-indicator";
  }

  get categoryUnreadIndicatorClass() {
    return "chat-channel-unread-indicator";
  }

  get chatUnreadIndicatorClass() {
    return "chat-channel-unread-indicator";
  }

  get rowClass() {
    return dConcatClass(
      "workspace-team-sidebar__row",
      "sidebar-row",
      this.args.chatMuted && "workspace-team-sidebar__row--muted",
      this.args.editable && "workspace-team-sidebar__row--editing",
      this.args.dragging && "workspace-team-sidebar__row--dragging",
      this.args.dropBefore && "workspace-team-sidebar__row--drop-before",
      this.args.dropAfter && "workspace-team-sidebar__row--drop-after"
    );
  }

  @action
  openChat(event) {
    if (this.args.editable) {
      event.preventDefault();
      return;
    }

    if (!this.args.chatPath) {
      event.preventDefault();
      return;
    }

    event.preventDefault();
    this.chatStateManager?.prefersFullPage();
    DiscourseURL.routeTo(this.args.chatPath);
  }

  @action
  startPointerDrag(event) {
    if (!this.args.editable) {
      return;
    }

    this.args.startPointerDrag?.(event);
  }

  <template>
    <li
      class="sidebar-section-link-wrapper"
      data-list-item-name={{@categoryLink.name}}
    >
      <div
        class={{dConcatClass
          this.rowClass
        }}
        data-workspace-category-id={{@categoryLink.category.id}}
        {{! eslint-disable-next-line ember/template-no-pointer-down-event-binding }}
        {{on "pointerdown" this.startPointerDrag}}
      >
        {{#if @editable}}
          <div
            class={{this.mainLinkClass}}
            title={{if this.mainLinkOpensChat @chatTitle @categoryLink.title}}
          >
            <span class="workspace-team-sidebar__main-link-prefix">
              <SectionLinkPrefix
                @prefixType={{@categoryLink.prefixType}}
                @prefixValue={{@categoryLink.prefixValue}}
                @prefixColor={{this.prefixColor}}
                @prefixBadge={{this.prefixBadge}}
              />

              {{#if this.mainLinkUnread}}
                <span class={{this.mainLinkUnreadIndicatorClass}}></span>
              {{/if}}
            </span>

            <span class="sidebar-section-link-content-text">
              {{@categoryLink.text}}
            </span>

            {{#if @categoryLink.badgeText}}
              <span class="sidebar-section-link-content-badge">
                {{@categoryLink.badgeText}}
              </span>
            {{/if}}
          </div>
        {{else if this.mainLinkOpensChat}}
          <button
            type="button"
            title={{@chatTitle}}
            aria-label={{@chatTitle}}
            class={{this.mainLinkClass}}
            {{on "click" this.openChat}}
          >
            <span class="workspace-team-sidebar__main-link-prefix">
              <SectionLinkPrefix
                @prefixType={{@categoryLink.prefixType}}
                @prefixValue={{@categoryLink.prefixValue}}
                @prefixColor={{this.prefixColor}}
                @prefixBadge={{this.prefixBadge}}
              />

              {{#if this.mainLinkUnread}}
                <span class={{this.mainLinkUnreadIndicatorClass}}></span>
              {{/if}}
            </span>

            <span class="sidebar-section-link-content-text">
              {{@categoryLink.text}}
            </span>

            {{#if @categoryLink.badgeText}}
              <span class="sidebar-section-link-content-badge">
                {{@categoryLink.badgeText}}
              </span>
            {{/if}}
          </button>
        {{else}}
          <LinkTo
            @route={{@categoryLink.route}}
            @models={{this.categoryModels}}
            @query={{this.categoryQuery}}
            @current-when={{@categoryLink.currentWhen}}
            @title={{@categoryLink.title}}
            class={{this.mainLinkClass}}
          >
            <span class="workspace-team-sidebar__main-link-prefix">
              <SectionLinkPrefix
                @prefixType={{@categoryLink.prefixType}}
                @prefixValue={{@categoryLink.prefixValue}}
                @prefixColor={{this.prefixColor}}
                @prefixBadge={{this.prefixBadge}}
              />

              {{#if this.mainLinkUnread}}
                <span class={{this.mainLinkUnreadIndicatorClass}}></span>
              {{/if}}
            </span>

            <span class="sidebar-section-link-content-text">
              {{@categoryLink.text}}
            </span>

            {{#if @categoryLink.badgeText}}
              <span class="sidebar-section-link-content-badge">
                {{@categoryLink.badgeText}}
              </span>
            {{/if}}
          </LinkTo>
        {{/if}}

        {{#if this.showModes}}
          <div class="workspace-team-sidebar__modes">
            {{#if @editable}}
              <span class={{this.categoryButtonClass}}>
                <span class="workspace-team-sidebar__mode-icon">
                  {{dIcon "list"}}

                  {{#if @categoryUnread}}
                    <span class={{this.categoryUnreadIndicatorClass}}></span>
                  {{/if}}
                </span>
              </span>
            {{else}}
              <LinkTo
                @route={{@categoryLink.route}}
                @models={{this.categoryModels}}
                @query={{this.categoryQuery}}
                @current-when={{@categoryLink.currentWhen}}
                @title={{@categoryTitle}}
                class={{this.categoryButtonClass}}
              >
                <span class="workspace-team-sidebar__mode-icon">
                  {{dIcon "list"}}

                  {{#if @categoryUnread}}
                    <span class={{this.categoryUnreadIndicatorClass}}></span>
                  {{/if}}
                </span>
              </LinkTo>
            {{/if}}

            {{#if @editable}}
              <span class={{this.chatButtonClass}}>
                <span class="workspace-team-sidebar__mode-icon">
                  {{dIcon "d-chat"}}

                  {{#if @chatUnread}}
                    <span class={{this.chatUnreadIndicatorClass}}></span>
                  {{/if}}
                </span>
              </span>
            {{else}}
              <button
                type="button"
                class={{this.chatButtonClass}}
                title={{@chatTitle}}
                aria-label={{@chatTitle}}
                disabled={{this.chatDisabled}}
                {{on "click" this.openChat}}
              >
                <span class="workspace-team-sidebar__mode-icon">
                  {{dIcon "d-chat"}}

                  {{#if @chatUnread}}
                    <span class={{this.chatUnreadIndicatorClass}}></span>
                  {{/if}}
                </span>
              </button>
            {{/if}}
          </div>
        {{/if}}

      </div>
    </li>
  </template>
}
