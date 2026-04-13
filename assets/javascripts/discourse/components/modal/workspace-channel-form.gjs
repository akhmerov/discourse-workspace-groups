import Component from "@glimmer/component";
import { Input, Textarea } from "@ember/component";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DToggleSwitch from "discourse/components/d-toggle-switch";
import ComboBox from "discourse/select-kit/components/combo-box";
import { i18n } from "discourse-i18n";

export default class WorkspaceChannelForm extends Component {
  get channelModeOptions() {
    return [
      {
        id: "both",
        name: i18n("discourse_workspace_groups.channel_mode_both"),
      },
      {
        id: "chat_only",
        name: i18n("discourse_workspace_groups.channel_mode_chat_only"),
      },
      {
        id: "category_only",
        name: i18n("discourse_workspace_groups.channel_mode_category_only"),
      },
    ];
  }

  get channelWideMentionsDescription() {
    return i18n("chat.settings.channel_wide_mentions_description", {
      channel: this.args.name?.trim() || "",
    });
  }

  @action
  updateName(event) {
    this.args.onNameChange?.(event.target.value);
  }

  @action
  updateDescription(event) {
    this.args.onDescriptionChange?.(event.target.value);
  }

  @action
  togglePrivate() {
    this.args.onPrivateToggle?.();
  }

  @action
  updateChannelMode(channelMode) {
    this.args.onChannelModeChange?.(channelMode);
  }

  @action
  toggleChannelWideMentions() {
    this.args.onChannelWideMentionsToggle?.();
  }

  <template>
    <label class="workspace-groups-create-channel-modal__field">
      <span class="workspace-groups-create-channel-modal__label">
        {{i18n "discourse_workspace_groups.channel_name"}}
      </span>
      <Input
        @value={{@name}}
        class="workspace-groups-create-channel-modal__input"
        autofocus={{@autofocus}}
        {{on "input" this.updateName}}
      />
    </label>

    <label class="workspace-groups-create-channel-modal__field">
      <span class="workspace-groups-create-channel-modal__label">
        {{i18n "discourse_workspace_groups.channel_description"}}
      </span>
      <Textarea
        @value={{@description}}
        class="workspace-groups-create-channel-modal__textarea"
        {{on "input" this.updateDescription}}
      />
    </label>

    {{#if @showChannelMode}}
      <div class="workspace-groups-create-channel-modal__field">
        <span class="workspace-groups-create-channel-modal__label">
          {{i18n "discourse_workspace_groups.channel_mode"}}
        </span>
        <ComboBox
          @value={{@channelMode}}
          @content={{this.channelModeOptions}}
          @options={{hash}}
          @onChange={{this.updateChannelMode}}
        />
        <p class="workspace-groups-create-channel-modal__help">
          {{i18n "discourse_workspace_groups.channel_mode_help"}}
        </p>
      </div>
    {{/if}}

    {{#if @showVisibility}}
      <div class="workspace-groups-create-channel-modal__field">
        <DToggleSwitch
          @state={{@isPrivate}}
          @label="discourse_workspace_groups.private_channel"
          {{on "click" this.togglePrivate}}
        />
        <p class="workspace-groups-create-channel-modal__help">
          {{i18n "discourse_workspace_groups.private_channel_help"}}
        </p>
      </div>
    {{/if}}

    {{#if @showChannelWideMentions}}
      <div class="workspace-groups-create-channel-modal__field">
        <DToggleSwitch
          @state={{@allowChannelWideMentions}}
          @label="chat.settings.channel_wide_mentions_label"
          {{on "click" this.toggleChannelWideMentions}}
        />
        <p class="workspace-groups-create-channel-modal__help">
          {{this.channelWideMentionsDescription}}
        </p>
      </div>
    {{/if}}
  </template>
}
