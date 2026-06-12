import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { isHex } from "discourse/components/sidebar/section-link";
import SectionLinkPrefix from "discourse/components/sidebar/section-link-prefix";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
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
    return concatClass(
      "workspace-team-sidebar__mode-button",
      this.args.chatMuted && "workspace-team-sidebar__mode-button--muted",
      this.args.categoryActive && "workspace-team-sidebar__mode-button--active"
    );
  }

  get chatButtonClass() {
    return concatClass(
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
    return concatClass(
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
    return concatClass(
      "workspace-team-sidebar__row",
      "sidebar-row",
      this.args.chatMuted && "workspace-team-sidebar__row--muted",
      this.args.editable && "workspace-team-sidebar__row--editing"
    );
  }

  get moveUpDisabled() {
    return !!(this.args.saving || this.args.moveUpDisabled);
  }

  get moveDownDisabled() {
    return !!(this.args.saving || this.args.moveDownDisabled);
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
  moveUp(event) {
    event.preventDefault();
    this.args.moveRow?.(this.args.categoryLink.category, this.args.sectionId, -1);
  }

  @action
  moveDown(event) {
    event.preventDefault();
    this.args.moveRow?.(this.args.categoryLink.category, this.args.sectionId, 1);
  }

  @action
  moveToSection(event) {
    const sectionId = event.target.value;

    if (!sectionId || sectionId === this.args.sectionId) {
      event.preventDefault();
      return;
    }

    this.args.moveToSection?.(this.args.categoryLink.category, sectionId);
  }

  <template>
    <li
      class="sidebar-section-link-wrapper"
      data-list-item-name={{@categoryLink.name}}
    >
      <div
        class={{concatClass
          this.rowClass
        }}
      >
        {{#if @editable}}
          <div class="workspace-team-sidebar__order-controls">
            <button
              type="button"
              title="Move up"
              aria-label="Move up"
              class="workspace-team-sidebar__order-button"
              disabled={{this.moveUpDisabled}}
              {{on "click" this.moveUp}}
            >
              {{icon "chevron-up"}}
            </button>
            <button
              type="button"
              title="Move down"
              aria-label="Move down"
              class="workspace-team-sidebar__order-button"
              disabled={{this.moveDownDisabled}}
              {{on "click" this.moveDown}}
            >
              {{icon "chevron-down"}}
            </button>
          </div>
        {{/if}}

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
                  {{icon "list"}}

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
                  {{icon "list"}}

                  {{#if @categoryUnread}}
                    <span class={{this.categoryUnreadIndicatorClass}}></span>
                  {{/if}}
                </span>
              </LinkTo>
            {{/if}}

            {{#if @editable}}
              <span class={{this.chatButtonClass}}>
                <span class="workspace-team-sidebar__mode-icon">
                  {{icon "d-chat"}}

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
                  {{icon "d-chat"}}

                  {{#if @chatUnread}}
                    <span class={{this.chatUnreadIndicatorClass}}></span>
                  {{/if}}
                </span>
              </button>
            {{/if}}
          </div>
        {{/if}}

        {{#if @editable}}
          <select
            title="Move to section"
            aria-label="Move to section"
            class="workspace-team-sidebar__section-select"
            value={{@sectionId}}
            disabled={{@saving}}
            {{on "change" this.moveToSection}}
          >
            {{#each @sectionOptions as |section|}}
              <option value={{section.id}}>
                {{section.title}}
              </option>
            {{/each}}
          </select>
        {{/if}}
      </div>
    </li>
  </template>
}
