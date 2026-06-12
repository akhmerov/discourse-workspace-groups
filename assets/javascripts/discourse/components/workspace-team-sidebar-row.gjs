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
      this.args.editable && "workspace-team-sidebar__row--editing",
      this.args.dragging && "workspace-team-sidebar__row--dragging"
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
  dragHasStarted(event) {
    if (!this.args.editable) {
      event.preventDefault();
      return;
    }

    const category = this.args.categoryLink.category;

    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", String(category.id));
    event.dataTransfer.setData(
      "application/x-workspace-category-id",
      String(category.id)
    );
    this.setDragImage(event);
    this.args.setDraggedCategory?.(category);
  }

  @action
  dragEnd() {
    this.clearDragImage();
    this.args.setDraggedCategory?.(null);
  }

  setDragImage(event) {
    const row = event.currentTarget.closest(".workspace-team-sidebar__row");

    if (!row || !event.dataTransfer?.setDragImage) {
      return;
    }

    const rowRect = row.getBoundingClientRect();
    const dragImage = row.cloneNode(true);

    dragImage.classList.add("workspace-team-sidebar__drag-image");
    dragImage.style.width = `${rowRect.width}px`;
    dragImage.style.position = "fixed";
    dragImage.style.top = "-1000px";
    dragImage.style.left = "-1000px";
    dragImage.style.pointerEvents = "none";
    document.body.appendChild(dragImage);
    event.dataTransfer.setDragImage(dragImage, 16, rowRect.height / 2);

    this.dragImage = dragImage;
    requestAnimationFrame(() => this.clearDragImage());
  }

  clearDragImage() {
    this.dragImage?.remove();
    this.dragImage = null;
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
          <div
            class="workspace-team-sidebar__drag-handle"
            title="Drag to reorder"
            draggable="true"
            {{on "dragstart" this.dragHasStarted}}
            {{on "dragend" this.dragEnd}}
          >
            {{icon "grip-lines"}}
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

      </div>
    </li>
  </template>
}
