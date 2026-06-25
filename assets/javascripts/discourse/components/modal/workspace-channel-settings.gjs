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

  @tracked name;
  @tracked description;
  @tracked isPrivate;
  @tracked channelMode;
  @tracked eventsEnabled;
  @tracked allowChannelWideMentions;
  @tracked color;
  @tracked styleType;
  @tracked emoji;
  @tracked saving = false;
  @tracked changingArchiveState = false;

  constructor() {
    super(...arguments);

    this.name = this.channel?.name || "";
    this.description = this.channel?.description_raw || this.channel?.description || "";
    this.isPrivate = this.channel?.visibility === "private";
    this.channelMode = this.channel?.mode || "both";
    this.eventsEnabled = this.channel?.events_enabled === true;
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
    return !this.saving && !this.changingArchiveState && this.name.trim().length > 0;
  }

  get archiveActionLabel() {
    return this.channel?.archived
      ? "discourse_workspace_groups.unarchive_channel"
      : "discourse_workspace_groups.archive_channel";
  }

  get canEditVisibility() {
    return Boolean(this.workspace?.can_create_private_channel);
  }

  get showChannelWideMentions() {
    return this.channelMode !== "category_only";
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
            color: this.color,
            style_type: this.styleType,
            emoji: this.emoji,
            ...(this.channelMode !== "category_only"
              ? {
                  allow_channel_wide_mentions: this.allowChannelWideMentions,
                }
              : {}),
          }
        }
      );

      setEventCategory(
        this.siteSettings,
        result.channel.id,
        result.channel.events_enabled
      );
      await this.args.model.onUpdate?.(result.channel);
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
      @title={{this.modalTitle}}
      @closeModal={{@closeModal}}
      @inline={{@inline}}
      class="workspace-groups-create-channel-modal workspace-groups-channel-settings-modal"
    >
      <:body>
        <WorkspaceChannelForm
          @name={{this.name}}
          @description={{this.description}}
          @isPrivate={{this.isPrivate}}
          @channelMode={{this.channelMode}}
          @eventsEnabled={{this.eventsEnabled}}
          @allowChannelWideMentions={{this.allowChannelWideMentions}}
          @color={{this.color}}
          @styleType={{this.styleType}}
          @emoji={{this.emoji}}
          @categoryId={{this.channel.id}}
          @autofocus={{true}}
          @showVisibility={{this.canEditVisibility}}
          @showChannelMode={{true}}
          @showEventsEnabled={{this.showEventsEnabled}}
          @showChannelWideMentions={{this.showChannelWideMentions}}
          @showCategoryStyle={{true}}
          @onNameChange={{this.updateName}}
          @onDescriptionChange={{this.updateDescription}}
          @onPrivateToggle={{this.togglePrivate}}
          @onChannelModeChange={{this.updateChannelMode}}
          @onEventsEnabledToggle={{this.toggleEventsEnabled}}
          @onChannelWideMentionsToggle={{this.toggleChannelWideMentions}}
          @onColorChange={{this.updateColor}}
          @onEmojiChange={{this.updateEmoji}}
        />
      </:body>
      <:footer>
        {{#if this.channel.can_view_members}}
          <DButton
            @action={{this.openMembers}}
            @label="discourse_workspace_groups.channel_members"
            @icon="user"
            class="btn-default"
            @disabled={{this.saving}}
          />
        {{/if}}
        <DButton
          @action={{this.saveChannel}}
          @label="discourse_workspace_groups.save_channel"
          class="btn-primary"
          @disabled={{not this.canSave}}
        />
        <DButton
          @action={{this.toggleArchiveState}}
          @label={{this.archiveActionLabel}}
          class="btn-default"
          @disabled={{this.saving}}
        />
        <DButton @action={{this.cancel}} @label="cancel" class="btn-default" />
      </:footer>
    </DModal>
  </template>
}
