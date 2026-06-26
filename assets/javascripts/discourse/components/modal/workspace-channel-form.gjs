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
import { not } from "discourse/truth-helpers";
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
        .concat(categories.map((category) => category.color?.toUpperCase()).filter(Boolean))
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

    {{#if @showEventsEnabled}}
      <div class="workspace-groups-create-channel-modal__field">
        <DToggleSwitch
          @state={{@eventsEnabled}}
          @label="discourse_workspace_groups.channel_events"
          {{on "click" this.toggleEventsEnabled}}
        />
        <p class="workspace-groups-create-channel-modal__help">
          {{i18n "discourse_workspace_groups.channel_events_help"}}
        </p>
      </div>
    {{/if}}

    {{#if @showCategoryStyle}}
      <div class="workspace-groups-create-channel-modal__field category-color-editor">
        <span class="workspace-groups-create-channel-modal__label">
          {{i18n "category.background_color"}}
        </span>
        <FKControlColor
          @field={{this.colorField}}
          @colors={{this.backgroundColors}}
          @usedColors={{this.usedBackgroundColors}}
          placeholder="RRGGBB"
        />
      </div>

      <div class="workspace-groups-create-channel-modal__field">
        <span class="workspace-groups-create-channel-modal__label">
          {{i18n "category.styles.emoji"}}
        </span>
        <div class="workspace-groups-create-channel-modal__emoji-row">
          <EmojiPicker
            @emoji={{@emoji}}
            @didSelectEmoji={{this.updateEmoji}}
            @btnClass="btn-default btn-emoji"
            @modalForMobile={{false}}
            @context="channel-emoji"
            @inline={{true}}
            @label={{this.emojiPickerLabel}}
          />
          <DButton
            @label="chat.channel_edit_name_slug_modal.reset_emoji"
            @action={{this.clearEmoji}}
            @disabled={{not @emoji}}
            class="btn-flat"
          />
        </div>
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
