import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input } from "@ember/component";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import UserChooser from "discourse/select-kit/components/user-chooser";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class WorkspaceVoiceCallDetails extends Component {
  @service router;
  @service voiceRooms;
  @service voiceWebrtc;
  @service workspaceVoice;
  @service messageBus;

  @tracked messages = [];
  @tracked text = "";
  @tracked usernames = [];
  @tracked inviting = false;
  @tracked inviteResult = "";
  subscription = null;

  willDestroy() {
    super.willDestroy(...arguments);
    this.unsubscribe();
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

  get audience() {
    return this.details.source_type === "dm"
      ? i18n("discourse_workspace_groups.voice.dm_audience")
      : i18n(
          this.details.allow_guests
            ? "discourse_workspace_groups.voice.audience"
            : "discourse_workspace_groups.voice.members_audience",
          {
            audience: this.details.audience,
          }
        );
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
  async syncSession() {
    if (!this.joined) {
      this.unsubscribe();
      this.messages = [];
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
      <section
        class="workspace-voice-call-details"
        {{didInsert this.syncSession}}
        {{didUpdate this.syncSession this.joined this.room.id}}
      >
        <p>{{this.audience}}</p>
        {{#if this.details.is_guest}}<p>{{i18n
              "discourse_workspace_groups.voice.guest"
            }}</p>{{/if}}
        {{#if this.hasGuests}}<p>{{i18n
              "discourse_workspace_groups.voice.guest_present"
              usernames=this.guestNames
            }}</p>{{/if}}
        <div class="workspace-voice-call-details__actions">
          {{#if this.details.conversation_url}}<a
              href={{this.details.conversation_url}}
            >{{i18n "discourse_workspace_groups.voice.conversation"}}</a>{{/if}}
          {{#if this.joined}}
            {{#if this.room.can_manage}}<DButton
                @action={{this.endCall}}
                @icon="phone-slash"
                @label="discourse_workspace_groups.voice.end"
              />{{/if}}
          {{/if}}
        </div>
        {{#if this.joined}}
          {{#if this.canInvite}}
            <p>{{i18n "discourse_workspace_groups.voice.invite_help"}}</p>
            <div class="workspace-voice-call-details__actions">
              <UserChooser
                @onChange={{this.chooseUsers}}
                @value={{this.usernames}}
              />
              <DButton
                @action={{this.invite}}
                @disabled={{this.inviting}}
                @icon="user-plus"
                @label="discourse_workspace_groups.voice.invite"
              />
            </div>
          {{/if}}
          {{#if this.inviteResult}}<p
              role="status"
            >{{this.inviteResult}}</p>{{/if}}
          <details class="workspace-voice-call-messages">
            <summary>{{i18n
                "discourse_workspace_groups.voice.messages"
              }}</summary>
            <p>{{i18n "discourse_workspace_groups.voice.messages_help"}}</p>
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
                @label="discourse_workspace_groups.voice.send"
              />
            </div>
          </details>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
