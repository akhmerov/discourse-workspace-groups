import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input } from "@ember/component";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import DMenu from "discourse/float-kit/components/d-menu";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import optionalService from "discourse/lib/optional-service";
import UserChooser from "discourse/select-kit/components/user-chooser";
import DButton from "discourse/ui-kit/d-button";
import DDropdownMenu from "discourse/ui-kit/d-dropdown-menu";
import DModal from "discourse/ui-kit/d-modal";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class WorkspaceVoiceCallDetails extends Component {
  @service router;
  @service workspaceVoice;
  @service messageBus;
  @optionalService voiceRooms;
  @optionalService voiceWebrtc;

  @tracked toolbarElement;
  @tracked bodyElement;
  @tracked showInvite = false;
  @tracked showMessages = false;
  @tracked messages = [];

  @tracked text = "";
  @tracked usernames = [];
  @tracked inviting = false;
  @tracked inviteResult = "";
  observer = null;
  resizeObserver = null;
  pageElement = null;
  subscription = null;

  willDestroy() {
    super.willDestroy(...arguments);
    this.unsubscribe();
    this.observer?.disconnect();
    this.resizeObserver?.disconnect();
    window.removeEventListener("resize", this.sizeRoom);
    this.pageElement?.classList.remove("workspace-voice-room-page");
  }

  get room() {
    if (this.router.currentRouteName !== "voice-room") {
      return null;
    }
    const model = getOwner(this).lookup("controller:voice-room")?.model;
    return this.voiceRooms.rooms.find((room) => room.id === model?.id) || model;
  }

  get details() {
    return this.room?.workspace_voice;
  }

  get joined() {
    return (
      this.room &&
      this.voiceWebrtc.connectionStateFor(this.room.id) === "connected"
    );
  }

  get hasGuests() {
    return this.room?.active_participants?.some(
      (user) => user.workspace_voice_guest
    );
  }

  get guestNames() {
    return this.room?.active_participants
      ?.filter((user) => user.workspace_voice_guest)
      .map((user) => user.username)
      .join(", ");
  }

  get canInvite() {
    return this.details.can_admit_guests;
  }

  unsubscribe() {
    if (this.subscription) {
      this.messageBus.unsubscribe(this.subscription, this.loadMessages);
      this.subscription = null;
    }
  }

  @action
  mountControls() {
    this.observer?.disconnect();
    this.observer = new MutationObserver(this.locateControls);
    this.observer.observe(document.body, { childList: true, subtree: true });
    this.resizeObserver?.disconnect();
    this.resizeObserver = new ResizeObserver(this.sizeRoom);
    window.addEventListener("resize", this.sizeRoom);
    this.locateControls();
    this.syncSession();
  }

  @action
  locateControls() {
    if (this.isDestroying) {
      return;
    }
    const toolbar = this.details
      ? document.querySelector(".voice-room-page__title-row")
      : null;
    const body = this.details
      ? document.querySelector(".voice-room-page__body")
      : null;
    const page = body?.closest(".voice-room-page");
    if (this.pageElement !== page) {
      this.pageElement?.classList.remove("workspace-voice-room-page");
      this.resizeObserver?.disconnect();
      this.pageElement = page;
      if (page) {
        page.classList.add("workspace-voice-room-page");
        this.resizeObserver?.observe(page.parentElement);
        for (const element of page.querySelectorAll(
          ".voice-room-page__controls, .voice-room-page__header"
        )) {
          this.resizeObserver?.observe(element);
        }
      }
    }
    this.sizeRoom();
    if (this.toolbarElement !== toolbar) {
      this.toolbarElement = toolbar;
    }
    if (this.bodyElement !== body) {
      this.bodyElement = body;
    }
  }

  @action
  sizeRoom() {
    if (!this.pageElement?.isConnected) {
      return;
    }
    const top = Math.max(
      0,
      this.pageElement.getBoundingClientRect().top + window.scrollY
    );
    this.pageElement.style.setProperty(
      "--workspace-voice-page-top",
      `${top}px`
    );
    for (const part of ["controls", "header"]) {
      const height =
        this.pageElement
          .querySelector(`.voice-room-page__${part}`)
          ?.getBoundingClientRect().height || 0;
      this.pageElement.style.setProperty(
        `--workspace-voice-${part}-height`,
        `${height}px`
      );
    }
  }

  @action
  openInvite() {
    this.inviteResult = "";
    this.showInvite = true;
  }

  @action
  closeInvite() {
    this.showInvite = false;
  }

  @action
  toggleMessages() {
    this.showMessages = !this.showMessages;
  }

  @action
  async syncSession() {
    if (!this.joined) {
      this.unsubscribe();
      this.messages = [];
      this.showInvite = false;
      this.showMessages = false;
      return;
    }
    const subscription = `/workspace-voice/messages/${this.details.binding_id}`;
    if (this.subscription !== subscription) {
      this.unsubscribe();
      this.subscription = subscription;
      this.messageBus.subscribe(subscription, this.loadMessages);
      await this.loadMessages();
    }
    if (this.workspaceVoice.pendingRingRoomId === this.room.id) {
      this.workspaceVoice.pendingRingRoomId = null;
      try {
        await ajax(`/workspace-groups/voice/rooms/${this.room.id}/ring`, {
          type: "POST",
        });
      } catch (error) {
        popupAjaxError(error);
      }
    }
  }

  @action
  async loadMessages() {
    if (!this.joined) {
      return;
    }
    const roomId = this.room.id;
    try {
      const result = await ajax(
        `/workspace-groups/voice/rooms/${roomId}/messages.json`
      );
      if (!this.isDestroying && this.room?.id === roomId && this.joined) {
        this.messages = result.messages;
      }
    } catch (error) {
      if (error.jqXHR?.status !== 403 && !this.isDestroying) {
        popupAjaxError(error);
      }
    }
  }

  @action
  async sendMessage() {
    if (!this.text.trim() || !this.joined) {
      return;
    }
    try {
      await ajax(`/workspace-groups/voice/rooms/${this.room.id}/messages`, {
        type: "POST",
        data: { text: this.text },
      });
      this.text = "";
      await this.loadMessages();
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  chooseUsers(usernames) {
    this.usernames = usernames;
  }

  @action
  async invite() {
    if (!this.usernames.length || !this.joined) {
      return;
    }
    this.inviting = true;
    try {
      const result = await ajax(`/voice/rooms/${this.room.id}/invites`, {
        type: "POST",
        data: { usernames: this.usernames },
      });
      this.usernames = result.skipped_usernames;
      this.inviteResult = i18n(
        result.skipped_usernames.length
          ? "discourse_workspace_groups.voice.invite_skipped"
          : "discourse_workspace_groups.voice.invite_sent"
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.inviting = false;
    }
  }

  @action
  async endCall() {
    try {
      await ajax(`/workspace-groups/voice/rooms/${this.room.id}/session`, {
        type: "DELETE",
      });
      await this.voiceWebrtc.leave(this.room);
    } catch (error) {
      popupAjaxError(error);
    }
  }

  <template>
    {{#if this.details}}
      <span
        hidden
        {{didInsert this.mountControls}}
        {{didUpdate this.syncSession this.joined this.room.id}}
      ></span>
      {{#if this.toolbarElement}}
        {{#in-element this.toolbarElement insertBefore=null}}
          <div class="workspace-voice-call-toolbar">
            {{#if this.details.is_guest}}
              <span
                class="workspace-voice-guest-badge"
                title={{i18n "discourse_workspace_groups.voice.guest"}}
              >{{i18n "discourse_workspace_groups.voice.guest_label"}}</span>
            {{/if}}
            {{#if this.hasGuests}}
              <span
                class="workspace-voice-guest-badge"
                title={{i18n
                  "discourse_workspace_groups.voice.guest_present"
                  usernames=this.guestNames
                }}
              >{{dIcon "user-group"}} {{this.guestNames}}</span>
            {{/if}}
            {{#if this.details.conversation_url}}
              <a
                aria-label={{i18n
                  "discourse_workspace_groups.voice.conversation"
                }}
                class="btn btn-transparent workspace-voice-conversation"
                href={{this.details.conversation_url}}
                title={{i18n "discourse_workspace_groups.voice.conversation"}}
              >{{dIcon "arrow-left"}}</a>
            {{/if}}
            {{#if this.joined}}
              <DButton
                aria-pressed={{this.showMessages}}
                class="btn-transparent workspace-voice-messages-toggle"
                @action={{this.toggleMessages}}
                @ariaLabel="discourse_workspace_groups.voice.messages"
                @icon="far-comment"
                @title="discourse_workspace_groups.voice.messages"
              />
              {{#if this.canInvite}}
                <DButton
                  class="btn-transparent workspace-voice-invite-toggle"
                  @action={{this.openInvite}}
                  @ariaLabel="discourse_workspace_groups.voice.invite"
                  @icon="user-plus"
                  @title="discourse_workspace_groups.voice.invite"
                />
              {{/if}}
              {{#if this.room.can_manage}}
                <DMenu
                  @ariaLabel={{i18n "discourse_workspace_groups.voice.options"}}
                  @icon="ellipsis-vertical"
                  @identifier="workspace-voice-options"
                  @modalForMobile={{true}}
                  @placement="bottom-end"
                  @title={{i18n "discourse_workspace_groups.voice.options"}}
                  @triggerClass="btn-transparent"
                >
                  <:content>
                    <DDropdownMenu as |menu|>
                      <menu.item><DButton
                          class="btn-transparent"
                          @action={{this.endCall}}
                          @icon="phone-slash"
                          @label="discourse_workspace_groups.voice.end"
                        /></menu.item>
                    </DDropdownMenu>
                  </:content>
                </DMenu>
              {{/if}}
            {{/if}}
          </div>
        {{/in-element}}
      {{/if}}
      {{#if this.joined}}
        {{#if this.showInvite}}
          <DModal
            class="voice-invite-modal workspace-voice-invite-modal"
            @closeModal={{this.closeInvite}}
            @title={{i18n "discourse_workspace_groups.voice.invite"}}
          >
            <:body>
              <p>{{i18n "discourse_workspace_groups.voice.invite_help"}}</p>
              <div class="voice-invite-modal__search-row">
                <UserChooser
                  class="voice-invite-modal__user-chooser"
                  @onChange={{this.chooseUsers}}
                  @value={{this.usernames}}
                />
                <DButton
                  class="btn-primary voice-invite-modal__send"
                  @action={{this.invite}}
                  @disabled={{this.inviting}}
                  @icon="paper-plane"
                  @label="discourse_workspace_groups.voice.invite"
                />
              </div>
              {{#if this.inviteResult}}<p
                  role="status"
                >{{this.inviteResult}}</p>{{/if}}
            </:body>
          </DModal>
        {{/if}}
        {{#if this.showMessages}}
          {{#if this.bodyElement}}
            {{#in-element this.bodyElement insertBefore=null}}
              <aside class="workspace-voice-call-messages">
                <header><h2>{{i18n
                      "discourse_workspace_groups.voice.messages"
                    }}</h2><DButton
                    class="btn-transparent"
                    @action={{this.toggleMessages}}
                    @ariaLabel="close"
                    @icon="xmark"
                    @title="close"
                  /></header>
                <p class="workspace-voice-messages-help">{{i18n
                    "discourse_workspace_groups.voice.messages_help"
                  }}</p>
                <div aria-live="polite" class="workspace-voice-messages">
                  {{#each this.messages as |message|}}<p><strong
                      >{{message.username}}:</strong>
                      <span>{{message.text}}</span></p>{{/each}}
                </div>
                <div class="workspace-voice-message-form">
                  <Input
                    aria-label={{i18n
                      "discourse_workspace_groups.voice.message_placeholder"
                    }}
                    maxlength="2000"
                    placeholder={{i18n
                      "discourse_workspace_groups.voice.message_placeholder"
                    }}
                    @value={{this.text}}
                  />
                  <DButton
                    @action={{this.sendMessage}}
                    @ariaLabel="discourse_workspace_groups.voice.send"
                    @icon="paper-plane"
                    @title="discourse_workspace_groups.voice.send"
                  />
                </div>
              </aside>
            {{/in-element}}
          {{/if}}
        {{/if}}
      {{/if}}
    {{/if}}
  </template>
}
