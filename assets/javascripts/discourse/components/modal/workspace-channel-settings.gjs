import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import { setEventCategory } from "../../lib/workspace-event-categories";
import WorkspaceChannelForm from "./workspace-channel-form";

export default class WorkspaceChannelSettingsModal extends Component {
  @service siteSettings;
  @service workspaceVoice;

  @tracked name;
  @tracked description;
  @tracked isPrivate;
  @tracked channelMode;
  @tracked eventsEnabled;
  @tracked voiceEnabled;
  @tracked voiceAllowGuests;
  @tracked allowChannelWideMentions;
  @tracked color;
  @tracked styleType;
  @tracked emoji;
  @tracked saving = false;
  @tracked changingArchiveState = false;

  constructor() {
    super(...arguments);

    this.name = this.channel?.name || "";
    this.description =
      this.channel?.description_raw || this.channel?.description || "";
    this.isPrivate = this.channel?.visibility === "private";
    this.channelMode = this.channel?.mode || "both";
    this.eventsEnabled = this.channel?.events_enabled === true;
    this.voiceEnabled = this.channel?.voice_enabled === true;
    this.voiceAllowGuests = this.channel?.voice_allow_guests !== false;
    this.allowChannelWideMentions =
      this.channel?.allow_channel_wide_mentions !== false;
    this.color = this.channel?.color || "0088CC";
    this.styleType = this.channel?.style_type || "square";
    this.emoji = this.styleType === "emoji" ? this.channel?.emoji : null;
  }

  get category() {
    return this.args.model.category;
  }

  get workspace() {
    return this.args.model.workspace || this.category;
  }

  get channel() {
    return this.args.model.channel;
  }

  get modalTitle() {
    return i18n("discourse_workspace_groups.channel_settings_title");
  }

  get canSave() {
    return (
      !this.saving && !this.changingArchiveState && this.name.trim().length > 0
    );
  }

  get archiveActionLabel() {
    return this.channel?.archived
      ? "discourse_workspace_groups.unarchive_channel"
      : "discourse_workspace_groups.archive_channel";
  }

  // Members of workspaces that let them manage channels get the settings without the
  // manager-only fields; the server rejects changes to those from them.
  get canManage() {
    return Boolean(this.channel?.can_manage_members);
  }

  get canEditVisibility() {
    return this.canManage && Boolean(this.workspace?.can_create_private_channel);
  }

  get showChannelWideMentions() {
    return this.canManage && this.channelMode !== "category_only";
  }

  get showEventsEnabled() {
    return this.channelMode !== "chat_only";
  }

  @action
  updateName(name) {
    this.name = name;
  }

  @action
  updateDescription(description) {
    this.description = description;
  }

  @action
  togglePrivate() {
    this.isPrivate = !this.isPrivate;
  }

  @action
  updateChannelMode(channelMode) {
    this.channelMode = channelMode;
    if (channelMode === "chat_only") {
      this.eventsEnabled = false;
    }
  }

  @action
  toggleVoiceAllowGuests() {
    this.voiceAllowGuests = !this.voiceAllowGuests;
  }

  @action
  toggleVoiceEnabled() {
    this.voiceEnabled = !this.voiceEnabled;
  }

  @action
  toggleEventsEnabled() {
    this.eventsEnabled = !this.eventsEnabled;
  }

  @action
  toggleChannelWideMentions() {
    this.allowChannelWideMentions = !this.allowChannelWideMentions;
  }

  @action
  updateColor(color) {
    this.color = color;
  }

  @action
  updateEmoji(emoji) {
    this.emoji = emoji;
    this.styleType = emoji ? "emoji" : "square";
  }

  @action
  async saveChannel() {
    if (!this.canSave) {
      return;
    }

    this.saving = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.category.id}/channels/${this.channel.id}`,
        {
          type: "PUT",
          data: {
            name: this.name.trim(),
            description: this.description.trim(),
            ...(this.canEditVisibility
              ? {
                  visibility: this.isPrivate ? "private" : "public",
                }
              : {}),
            channel_mode: this.channelMode,
            events_enabled: this.showEventsEnabled && this.eventsEnabled,
            ...(this.siteSettings.voice_enabled
              ? { voice_enabled: this.voiceEnabled }
              : {}),
            ...(this.siteSettings.voice_enabled && this.canManage
              ? { voice_allow_guests: this.voiceAllowGuests }
              : {}),
            color: this.color,
            style_type: this.styleType,
            emoji: this.emoji,
            ...(this.showChannelWideMentions
              ? {
                  allow_channel_wide_mentions: this.allowChannelWideMentions,
                }
              : {}),
          },
        }
      );

      setEventCategory(
        this.siteSettings,
        result.channel.id,
        result.channel.events_enabled
      );
      await this.args.model.onUpdate?.(result.channel);
      await this.workspaceVoice.refresh();
      this.args.closeModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async toggleArchiveState() {
    if (this.saving || this.changingArchiveState) {
      return;
    }

    this.changingArchiveState = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.category.id}/channels/${this.channel.id}/archive`,
        {
          type: this.channel.archived ? "DELETE" : "POST",
        }
      );

      await this.args.model.onUpdate?.(result.channel);
      await this.workspaceVoice.refresh();
      this.args.closeModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.changingArchiveState = false;
    }
  }

  @action
  openMembers() {
    this.args.closeModal();
    this.args.model.onOpenMembers?.();
  }

  @action
  cancel() {
    this.args.closeModal();
  }

  <template>
    <DModal
      class="workspace-groups-create-channel-modal workspace-groups-channel-settings-modal"
      @closeModal={{@closeModal}}
      @inline={{@inline}}
      @title={{this.modalTitle}}
    >
      <:body>
        <WorkspaceChannelForm
          @allowChannelWideMentions={{this.allowChannelWideMentions}}
          @autofocus={{this.canManage}}
          @categoryId={{this.channel.id}}
          @channelMode={{this.channelMode}}
          @color={{this.color}}
          @description={{this.description}}
          @emoji={{this.emoji}}
          @eventsEnabled={{this.eventsEnabled}}
          @hideName={{not this.canManage}}
          @hideVoiceAllowGuests={{not this.canManage}}
          @isPrivate={{this.isPrivate}}
          @name={{this.name}}
          @onChannelModeChange={{this.updateChannelMode}}
          @onChannelWideMentionsToggle={{this.toggleChannelWideMentions}}
          @onColorChange={{this.updateColor}}
          @onDescriptionChange={{this.updateDescription}}
          @onEmojiChange={{this.updateEmoji}}
          @onEventsEnabledToggle={{this.toggleEventsEnabled}}
          @onNameChange={{this.updateName}}
          @onPrivateToggle={{this.togglePrivate}}
          @onVoiceAllowGuestsToggle={{this.toggleVoiceAllowGuests}}
          @onVoiceEnabledToggle={{this.toggleVoiceEnabled}}
          @showCategoryStyle={{true}}
          @showChannelMode={{true}}
          @showChannelWideMentions={{this.showChannelWideMentions}}
          @showEventsEnabled={{this.showEventsEnabled}}
          @showVisibility={{this.canEditVisibility}}
          @showVoiceEnabled={{this.siteSettings.voice_enabled}}
          @styleType={{this.styleType}}
          @voiceAllowGuests={{this.voiceAllowGuests}}
          @voiceEnabled={{this.voiceEnabled}}
        />
      </:body>
      <:footer>
        {{#if this.channel.can_view_members}}
          <DButton
            class="btn-default"
            @action={{this.openMembers}}
            @disabled={{this.saving}}
            @icon="user"
            @label="discourse_workspace_groups.channel_members"
          />
        {{/if}}
        <DButton
          class="btn-primary"
          @action={{this.saveChannel}}
          @disabled={{not this.canSave}}
          @label="discourse_workspace_groups.save_channel"
        />
        <DButton
          class="btn-default"
          @action={{this.toggleArchiveState}}
          @disabled={{this.saving}}
          @label={{this.archiveActionLabel}}
        />
        <DButton class="btn-default" @action={{this.cancel}} @label="cancel" />
      </:footer>
    </DModal>
  </template>
}
