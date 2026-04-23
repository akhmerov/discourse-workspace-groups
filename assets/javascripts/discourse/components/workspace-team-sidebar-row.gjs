import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { isHex } from "discourse/components/sidebar/section-link";
import SectionLinkPrefix from "discourse/components/sidebar/section-link-prefix";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import discourseLater from "discourse/lib/later";
import DiscourseURL from "discourse/lib/url";

export default class WorkspaceTeamSidebarRow extends Component {
  @service("chat-state-manager") chatStateManager;

  @tracked dragCssClass;
  dragCount = 0;

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

  get mainLinkClass() {
    return concatClass(
      "workspace-team-sidebar__main-link",
      "sidebar-section-link",
      this.args.chatMuted && "sidebar-section-link--muted",
      this.args.editable && "workspace-team-sidebar__main-link--editing",
      this.mainLinkActive && "active"
    );
  }

  get mainLinkActive() {
    if (this.mainLinkOpensChat) {
      return this.args.chatActive;
    }

    return this.args.categoryActive;
  }

  get rowClass() {
    return concatClass(
      "workspace-team-sidebar__row",
      "sidebar-row",
      this.args.chatMuted && "workspace-team-sidebar__row--muted",
      this.args.editable && "workspace-team-sidebar__row--editing",
      this.dragCssClass
    );
  }

  isAboveElement(event) {
    event.preventDefault();
    const target = event.currentTarget;
    const domRect = target.getBoundingClientRect();
    return event.clientY - domRect.top < domRect.height / 2;
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
  dragHasStarted(event) {
    if (!this.args.editable || this.args.dragDisabled) {
      event.preventDefault();
      return;
    }

    event.dataTransfer.effectAllowed = "move";
    this.args.setDraggedCategory?.(this.args.categoryLink.category);
    this.dragCssClass = "dragging";
  }

  @action
  dragOver(event) {
    if (!this.args.editable || this.args.dragDisabled) {
      return;
    }

    event.preventDefault();

    if (this.dragCssClass !== "dragging") {
      this.dragCssClass = this.isAboveElement(event) ? "drag-above" : "drag-below";
    }
  }

  @action
  dragEnter() {
    if (!this.args.editable || this.args.dragDisabled) {
      return;
    }

    this.dragCount++;
  }

  @action
  dragLeave() {
    if (!this.args.editable || this.args.dragDisabled) {
      return;
    }

    this.dragCount--;

    if (
      this.dragCount === 0 &&
      (this.dragCssClass === "drag-above" || this.dragCssClass === "drag-below")
    ) {
      discourseLater(() => {
        this.dragCssClass = null;
      }, 10);
    }
  }

  @action
  dropItem(event) {
    if (!this.args.editable || this.args.dragDisabled) {
      return;
    }

    event.stopPropagation();
    this.dragCount = 0;
    this.args.reorderCallback?.(
      this.args.categoryLink.category,
      this.isAboveElement(event)
    );
    this.dragCssClass = null;
  }

  @action
  dragEnd() {
    this.dragCount = 0;
    this.dragCssClass = null;
    this.args.setDraggedCategory?.(null);
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
        draggable={{if @editable "true" "false"}}
        {{on "dragstart" this.dragHasStarted}}
        {{on "dragover" this.dragOver}}
        {{on "dragenter" this.dragEnter}}
        {{on "dragleave" this.dragLeave}}
        {{on "dragend" this.dragEnd}}
        {{on "drop" this.dropItem}}
      >
        {{#if @editable}}
          <div class="workspace-team-sidebar__drag-handle">
            {{icon "grip-lines"}}
          </div>
        {{/if}}

        {{#if @editable}}
          <div
            class={{this.mainLinkClass}}
            title={{if this.mainLinkOpensChat @chatTitle @categoryLink.title}}
          >
            <SectionLinkPrefix
              @prefixType={{@categoryLink.prefixType}}
              @prefixValue={{@categoryLink.prefixValue}}
              @prefixColor={{this.prefixColor}}
              @prefixBadge={{this.prefixBadge}}
            />

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
            <SectionLinkPrefix
              @prefixType={{@categoryLink.prefixType}}
              @prefixValue={{@categoryLink.prefixValue}}
              @prefixColor={{this.prefixColor}}
              @prefixBadge={{this.prefixBadge}}
            />

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
            <SectionLinkPrefix
              @prefixType={{@categoryLink.prefixType}}
              @prefixValue={{@categoryLink.prefixValue}}
              @prefixColor={{this.prefixColor}}
              @prefixBadge={{this.prefixBadge}}
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
        {{/if}}

        <div class="workspace-team-sidebar__modes">
          {{#if this.categoryAvailable}}
            {{#if @editable}}
              <span class={{this.categoryButtonClass}}>
                <span class="workspace-team-sidebar__mode-icon">
                  {{icon "list"}}

                  {{#if @categoryUnread}}
                    <span class="chat-channel-unread-indicator"></span>
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
                    <span class="chat-channel-unread-indicator"></span>
                  {{/if}}
                </span>
              </LinkTo>
            {{/if}}
          {{/if}}

          {{#if this.chatAvailable}}
            {{#if @editable}}
              <span class={{this.chatButtonClass}}>
                <span class="workspace-team-sidebar__mode-icon">
                  {{icon "d-chat"}}

                  {{#if @chatUnread}}
                    <span class="chat-channel-unread-indicator"></span>
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
                    <span class="chat-channel-unread-indicator"></span>
                  {{/if}}
                </span>
              </button>
            {{/if}}
          {{/if}}
        </div>
      </div>
    </li>
  </template>
}
