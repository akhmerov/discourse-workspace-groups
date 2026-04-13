import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import WorkspaceChannelForm from "./workspace-channel-form";

export default class WorkspaceChannelSettingsModal extends Component {
  @tracked name;
  @tracked description;
  @tracked isPrivate;
  @tracked channelMode;
  @tracked allowChannelWideMentions;
  @tracked saving = false;
  @tracked changingArchiveState = false;

  constructor() {
    super(...arguments);

    this.name = this.channel?.name || "";
    this.description = this.channel?.description_raw || this.channel?.description || "";
    this.isPrivate = this.channel?.visibility === "private";
    this.channelMode = this.channel?.mode || "both";
    this.allowChannelWideMentions =
      this.channel?.allow_channel_wide_mentions !== false;
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
  }

  @action
  toggleChannelWideMentions() {
    this.allowChannelWideMentions = !this.allowChannelWideMentions;
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
            ...(this.channelMode !== "category_only"
              ? {
                  allow_channel_wide_mentions: this.allowChannelWideMentions,
                }
              : {}),
          }
        }
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
          @allowChannelWideMentions={{this.allowChannelWideMentions}}
          @autofocus={{true}}
          @showVisibility={{this.canEditVisibility}}
          @showChannelMode={{true}}
          @showChannelWideMentions={{this.showChannelWideMentions}}
          @onNameChange={{this.updateName}}
          @onDescriptionChange={{this.updateDescription}}
          @onPrivateToggle={{this.togglePrivate}}
          @onChannelModeChange={{this.updateChannelMode}}
          @onChannelWideMentionsToggle={{this.toggleChannelWideMentions}}
        />
      </:body>
      <:footer>
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
