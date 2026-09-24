import Component from "@glimmer/component";
import { Input, Textarea } from "@ember/component";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import EmojiPicker from "discourse/components/emoji-picker";
import FKControlColor from "discourse/form-kit/components/fk/control/color";
import { uniqueItemsFromArray } from "discourse/lib/array-tools";
import ComboBox from "discourse/select-kit/components/combo-box";
import { and, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DToggleSwitch from "discourse/ui-kit/d-toggle-switch";
import { i18n } from "discourse-i18n";

export default class WorkspaceChannelForm extends Component {
  @service site;
  @service siteSettings;

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

  get backgroundColors() {
    const categories = this.site.get("categoriesList") || [];
    return uniqueItemsFromArray(
      this.siteSettings.category_colors
        .split("|")
        .filter(Boolean)
        .map((color) => color.toUpperCase())
        .concat(
          categories
            .map((category) => category.color?.toUpperCase())
            .filter(Boolean)
        )
    );
  }

  get usedBackgroundColors() {
    const categories = this.site.get("categoriesList") || [];
    return categories
      .map((category) => {
        return Number(category.id) === Number(this.args.categoryId) &&
          this.args.color?.toUpperCase() === category.color?.toUpperCase()
          ? null
          : category.color?.toUpperCase();
      })
      .filter(Boolean);
  }

  get emojiPickerLabel() {
    return this.args.emoji ? null : i18n("category.select_emoji");
  }

  get colorField() {
    return {
      value: this.args.color,
      hasExplicitType: true,
      set: (value) => this.updateColorValue(value),
    };
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
  toggleEventsEnabled() {
    this.args.onEventsEnabledToggle?.();
  }

  @action
  updateChannelMode(channelMode) {
    this.args.onChannelModeChange?.(channelMode);
  }

  @action
  toggleChannelWideMentions() {
    this.args.onChannelWideMentionsToggle?.();
  }

  updateColorValue(color) {
    this.args.onColorChange?.(color?.toUpperCase().replace(/^#/, ""));
  }

  @action
  updateEmoji(emoji) {
    this.args.onEmojiChange?.(emoji);
  }

  @action
  clearEmoji() {
    this.args.onEmojiChange?.(null);
  }

  <template>
    {{#unless @hideName}}
      <label class="workspace-groups-create-channel-modal__field">
        <span class="workspace-groups-create-channel-modal__label">
          {{i18n "discourse_workspace_groups.channel_name"}}
        </span>
        <Input
          autofocus={{@autofocus}}
          class="workspace-groups-create-channel-modal__input"
          @value={{@name}}
          {{on "input" this.updateName}}
        />
      </label>
    {{/unless}}

    <label class="workspace-groups-create-channel-modal__field">
      <span class="workspace-groups-create-channel-modal__label">
        {{i18n "discourse_workspace_groups.channel_description"}}
      </span>
      <Textarea
        class="workspace-groups-create-channel-modal__textarea"
        @value={{@description}}
        {{on "input" this.updateDescription}}
      />
    </label>

    {{#if @showChannelMode}}
      <div class="workspace-groups-create-channel-modal__field">
        <span class="workspace-groups-create-channel-modal__label">
          {{i18n "discourse_workspace_groups.channel_mode"}}
        </span>
        <ComboBox
          @content={{this.channelModeOptions}}
          @onChange={{this.updateChannelMode}}
          @options={{hash}}
          @value={{@channelMode}}
        />
        <p class="workspace-groups-create-channel-modal__help">
          {{i18n "discourse_workspace_groups.channel_mode_help"}}
        </p>
      </div>
    {{/if}}

    {{#if @showVoiceEnabled}}
      <div class="workspace-groups-create-channel-modal__field">
        <DToggleSwitch
          @label="discourse_workspace_groups.voice.enable"
          @state={{@voiceEnabled}}
          {{on "click" @onVoiceEnabledToggle}}
        />
        <p class="workspace-groups-create-channel-modal__help">{{i18n
            "discourse_workspace_groups.voice.enable_help"
          }}</p>
      </div>
      {{#if (and @voiceEnabled (not @hideVoiceAllowGuests))}}
        <DToggleSwitch
          @label="discourse_workspace_groups.voice.allow_guests"
          @state={{@voiceAllowGuests}}
          {{on "click" @onVoiceAllowGuestsToggle}}
        />
        <p class="workspace-groups-field-description">{{i18n
            "discourse_workspace_groups.voice.allow_guests_help"
          }}</p>
      {{/if}}
    {{/if}}

    {{#if @showEventsEnabled}}
      <div class="workspace-groups-create-channel-modal__field">
        <DToggleSwitch
          @label="discourse_workspace_groups.channel_events"
          @state={{@eventsEnabled}}
          {{on "click" this.toggleEventsEnabled}}
        />
        <p class="workspace-groups-create-channel-modal__help">
          {{i18n "discourse_workspace_groups.channel_events_help"}}
        </p>
      </div>
    {{/if}}

    {{#if @showCategoryStyle}}
      <div
        class="workspace-groups-create-channel-modal__field category-color-editor"
      >
        <span class="workspace-groups-create-channel-modal__label">
          {{i18n "category.background_color"}}
        </span>
        <FKControlColor
          placeholder="RRGGBB"
          @colors={{this.backgroundColors}}
          @field={{this.colorField}}
          @usedColors={{this.usedBackgroundColors}}
        />
      </div>

      <div class="workspace-groups-create-channel-modal__field">
        <span class="workspace-groups-create-channel-modal__label">
          {{i18n "category.styles.emoji"}}
        </span>
        <div class="workspace-groups-create-channel-modal__emoji-row">
          <EmojiPicker
            @btnClass="btn-default btn-emoji"
            @context="channel-emoji"
            @didSelectEmoji={{this.updateEmoji}}
            @emoji={{@emoji}}
            @inline={{true}}
            @label={{this.emojiPickerLabel}}
            @modalForMobile={{false}}
          />
          <DButton
            class="btn-flat"
            @action={{this.clearEmoji}}
            @disabled={{not @emoji}}
            @label="chat.channel_edit_name_slug_modal.reset_emoji"
          />
        </div>
      </div>
    {{/if}}

    {{#if @showVisibility}}
      <div class="workspace-groups-create-channel-modal__field">
        <DToggleSwitch
          @label="discourse_workspace_groups.private_channel"
          @state={{@isPrivate}}
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
          @label="chat.settings.channel_wide_mentions_label"
          @state={{@allowChannelWideMentions}}
          {{on "click" this.toggleChannelWideMentions}}
        />
        <p class="workspace-groups-create-channel-modal__help">
          {{this.channelWideMentionsDescription}}
        </p>
      </div>
    {{/if}}
  </template>
}
