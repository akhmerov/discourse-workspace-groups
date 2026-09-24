import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { isHex } from "discourse/components/sidebar/section-link";
import SectionLinkPrefix from "discourse/components/sidebar/section-link-prefix";
import optionalService from "discourse/lib/optional-service";
import DiscourseURL from "discourse/lib/url";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { isEventCategory } from "../lib/workspace-event-categories";

export default class WorkspaceTeamSidebarRow extends Component {
  @service("chat-state-manager") chatStateManager;
  @service siteSettings;
  @service workspaceVoice;
  @optionalService voiceRooms;

  get voiceAvailable() {
    const id = this.args.category?.id || this.args.categoryLink.category?.id;
    return this.workspaceVoice.channels.some(
      (channel) => channel.category_id === id
    );
  }

  get voiceParticipantCount() {
    const channel = this.workspaceVoice.channels.find(
      (item) => item.category_id === this.voiceCategoryId
    );
    return (
      this.voiceRooms?.rooms.find((room) => room.id === channel?.room?.id)
        ?.active_participants?.length || 0
    );
  }

  get voiceButtonClass() {
    return dConcatClass(
      "workspace-team-sidebar__mode-button workspace-voice-channel-link",
      this.args.voiceActive && "workspace-team-sidebar__mode-button--active"
    );
  }

  get voiceCategoryId() {
    return this.args.category?.id || this.args.categoryLink.category?.id;
  }

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

  get mainPrefixType() {
    return this.useChatMainPrefix ? "icon" : this.args.categoryLink.prefixType;
  }

  get mainPrefixValue() {
    return this.useChatMainPrefix
      ? "d-chat"
      : this.args.categoryLink.prefixValue;
  }

  get mainPrefixColor() {
    return this.prefixColor;
  }

  get mainPrefixBadge() {
    return this.useChatMainPrefix ? null : this.prefixBadge;
  }

  get useChatMainPrefix() {
    return this.mainLinkOpensChat && !this.args.categoryLink.category?.emoji;
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

  get categoryModeIcon() {
    return isEventCategory(this.siteSettings, this.args.category)
      ? "calendar-day"
      : "list";
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
      this.mainLinkHighlighted && "active"
    );
  }

  // The block knows the one channel being viewed. Core's route-list current-when would
  // mark every topics-and-chat channel active on any category page.
  get mainLinkHighlighted() {
    return !!(this.args.isActive && !this.args.editable);
  }

  get categoryModeActive() {
    return !!this.args.categoryActive;
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
      this.args.dropAfter && "workspace-team-sidebar__row--drop-after",
      this.args.isActive &&
        !this.args.editable &&
        "workspace-team-sidebar__row--active"
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

    // Let the browser open modified clicks in a new tab or window.
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button > 0) {
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
        class={{dConcatClass this.rowClass}}
        data-workspace-category-id={{@categoryLink.category.id}}
        data-workspace-sidebar-section-id={{@sidebarSectionId}}
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
                @prefixBadge={{this.mainPrefixBadge}}
                @prefixColor={{this.mainPrefixColor}}
                @prefixType={{this.mainPrefixType}}
                @prefixValue={{this.mainPrefixValue}}
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
          <a
            aria-current={{if this.mainLinkActive "page"}}
            aria-label={{@chatTitle}}
            class={{this.mainLinkClass}}
            href={{@chatPath}}
            title={{@chatTitle}}
            {{on "click" this.openChat}}
          >
            <span class="workspace-team-sidebar__main-link-prefix">
              <SectionLinkPrefix
                @prefixBadge={{this.mainPrefixBadge}}
                @prefixColor={{this.mainPrefixColor}}
                @prefixType={{this.mainPrefixType}}
                @prefixValue={{this.mainPrefixValue}}
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
          </a>
        {{else}}
          <LinkTo
            aria-current={{if this.mainLinkActive "page"}}
            class={{this.mainLinkClass}}
            @current-when={{this.mainLinkHighlighted}}
            @models={{this.categoryModels}}
            @query={{this.categoryQuery}}
            @route={{@categoryLink.route}}
            @title={{@categoryLink.title}}
          >
            <span class="workspace-team-sidebar__main-link-prefix">
              <SectionLinkPrefix
                @prefixBadge={{this.mainPrefixBadge}}
                @prefixColor={{this.mainPrefixColor}}
                @prefixType={{this.mainPrefixType}}
                @prefixValue={{this.mainPrefixValue}}
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

        {{#if this.voiceAvailable}}
          <LinkTo
            aria-current={{if @voiceActive "page"}}
            class={{this.voiceButtonClass}}
            @model={{this.voiceCategoryId}}
            @route="workspace-voice.channel"
            @title={{i18n "discourse_workspace_groups.voice.title"}}
          >
            {{dIcon "microphone"}}
            {{#if this.voiceParticipantCount}}<span
                class="workspace-voice-channel-count"
              >{{this.voiceParticipantCount}}</span>{{/if}}
          </LinkTo>
        {{/if}}
        {{#if this.showModes}}
          <div class="workspace-team-sidebar__modes">
            {{#if @editable}}
              <span class={{this.categoryButtonClass}}>
                <span class="workspace-team-sidebar__mode-icon">
                  {{dIcon this.categoryModeIcon}}

                  {{#if @categoryUnread}}
                    <span class={{this.categoryUnreadIndicatorClass}}></span>
                  {{/if}}
                </span>
              </span>
            {{else}}
              <LinkTo
                class={{this.categoryButtonClass}}
                @current-when={{this.categoryModeActive}}
                @models={{this.categoryModels}}
                @query={{this.categoryQuery}}
                @route={{@categoryLink.route}}
                @title={{@categoryTitle}}
              >
                <span class="workspace-team-sidebar__mode-icon">
                  {{dIcon this.categoryModeIcon}}

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
              {{#if this.chatDisabled}}
                <button
                  aria-label={{@chatTitle}}
                  class={{this.chatButtonClass}}
                  disabled={{true}}
                  title={{@chatTitle}}
                  type="button"
                >
                  <span class="workspace-team-sidebar__mode-icon">
                    {{dIcon "d-chat"}}
                  </span>
                </button>
              {{else}}
                <a
                  aria-current={{if @chatActive "page"}}
                  aria-label={{@chatTitle}}
                  class={{this.chatButtonClass}}
                  href={{@chatPath}}
                  title={{@chatTitle}}
                  {{on "click" this.openChat}}
                >
                  <span class="workspace-team-sidebar__mode-icon">
                    {{dIcon "d-chat"}}

                    {{#if @chatUnread}}
                      <span class={{this.chatUnreadIndicatorClass}}></span>
                    {{/if}}
                  </span>
                </a>
              {{/if}}
            {{/if}}
          </div>
        {{/if}}

      </div>
    </li>
  </template>
}
