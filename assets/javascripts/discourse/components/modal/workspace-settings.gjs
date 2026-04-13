import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input, Textarea } from "@ember/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import DToggleSwitch from "discourse/components/d-toggle-switch";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { has, not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default class WorkspaceSettingsModal extends Component {
  @tracked description;
  @tracked publicRead;
  @tracked membersCanCreateChannels;
  @tracked membersCanCreatePrivateChannels;
  @tracked autoJoinChannelIds;
  @tracked autoJoinChannelsFilter = "";
  @tracked saving = false;

  constructor() {
    super(...arguments);

    this.description = this.workspace?.about_raw || "";
    this.publicRead = Boolean(this.workspace?.public_read);
    this.membersCanCreateChannels = Boolean(
      this.workspace?.members_can_create_channels
    );
    this.membersCanCreatePrivateChannels = Boolean(
      this.workspace?.members_can_create_private_channels
    );
    this.autoJoinChannelIds = this.workspace?.auto_join_channel_ids || [];
  }

  get workspace() {
    return this.args.model.workspace;
  }

  get autoJoinChannelOptions() {
    return [...(this.workspace?.auto_join_channel_options || [])].sort(
      (left, right) => left.name.localeCompare(right.name)
    );
  }

  get selectedAutoJoinChannelIds() {
    return new Set(this.autoJoinChannelIds || []);
  }

  get filteredAutoJoinChannelOptions() {
    const filter = this.autoJoinChannelsFilter.trim().toLocaleLowerCase();

    return this.autoJoinChannelOptions
      .filter((option) => {
        return !filter || option.name.toLocaleLowerCase().includes(filter);
      })
      .sort((left, right) => {
        const leftSelected = this.selectedAutoJoinChannelIds.has(left.id);
        const rightSelected = this.selectedAutoJoinChannelIds.has(right.id);

        if (leftSelected !== rightSelected) {
          return leftSelected ? -1 : 1;
        }

        return left.name.localeCompare(right.name);
      });
  }

  get modalTitle() {
    return i18n("discourse_workspace_groups.workspace_settings_title");
  }

  get canSave() {
    return !this.saving;
  }

  @action
  togglePublicRead() {
    this.publicRead = !this.publicRead;
  }

  @action
  toggleMembersCanCreateChannels() {
    this.membersCanCreateChannels = !this.membersCanCreateChannels;

    if (!this.membersCanCreateChannels) {
      this.membersCanCreatePrivateChannels = false;
    }
  }

  @action
  toggleMembersCanCreatePrivateChannels() {
    if (!this.membersCanCreateChannels) {
      return;
    }

    this.membersCanCreatePrivateChannels =
      !this.membersCanCreatePrivateChannels;
  }

  @action
  updateAutoJoinChannelsFilter(event) {
    this.autoJoinChannelsFilter = event.target.value;
  }

  @action
  toggleAutoJoinChannel(channelId, event) {
    const nextIds = new Set(this.autoJoinChannelIds || []);

    if (event.target.checked) {
      nextIds.add(channelId);
    } else {
      nextIds.delete(channelId);
    }

    this.autoJoinChannelIds = [...nextIds];
  }

  @action
  async saveWorkspace() {
    if (!this.canSave) {
      return;
    }

    this.saving = true;

    try {
      const result = await ajax(`/workspace-groups/workspaces/${this.workspace.id}`, {
        type: "PUT",
        data: {
          description: this.description.trim(),
          public_read: this.publicRead,
          members_can_create_channels: this.membersCanCreateChannels,
          members_can_create_private_channels:
            this.membersCanCreatePrivateChannels,
          auto_join_channel_ids: this.autoJoinChannelIds,
        },
      });

      await this.args.model.onUpdate?.(result.workspace);
      this.args.closeModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
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
      class="workspace-groups-create-channel-modal workspace-groups-workspace-settings-modal"
    >
      <:body>
        <label class="workspace-groups-create-channel-modal__field">
          <span class="workspace-groups-create-channel-modal__label">
            {{i18n "discourse_workspace_groups.workspace_description"}}
          </span>
          <Textarea
            @value={{this.description}}
            class="workspace-groups-create-channel-modal__textarea"
          />
        </label>

        <div class="workspace-groups-create-channel-modal__field">
          <DToggleSwitch
            @state={{this.publicRead}}
            @label="discourse_workspace_groups.public_workspace"
            {{on "click" this.togglePublicRead}}
          />
          <p class="workspace-groups-create-channel-modal__help">
            {{i18n "discourse_workspace_groups.public_workspace_help"}}
          </p>
        </div>

        <div class="workspace-groups-create-channel-modal__field">
          <DToggleSwitch
            @state={{this.membersCanCreateChannels}}
            @label="discourse_workspace_groups.members_can_create_channels"
            {{on "click" this.toggleMembersCanCreateChannels}}
          />
          <p class="workspace-groups-create-channel-modal__help">
            {{i18n
              "discourse_workspace_groups.members_can_create_channels_help"
            }}
          </p>
        </div>

        <div class="workspace-groups-create-channel-modal__field">
          <DToggleSwitch
            @state={{this.membersCanCreatePrivateChannels}}
            @label="discourse_workspace_groups.members_can_create_private_channels"
            disabled={{not this.membersCanCreateChannels}}
            {{on "click" this.toggleMembersCanCreatePrivateChannels}}
          />
          <p class="workspace-groups-create-channel-modal__help">
            {{i18n
              "discourse_workspace_groups.members_can_create_private_channels_help"
            }}
          </p>
        </div>

        <div class="workspace-groups-create-channel-modal__field">
          <span class="workspace-groups-create-channel-modal__label">
            {{i18n "discourse_workspace_groups.auto_join_channels"}}
          </span>
          <Input
            @value={{this.autoJoinChannelsFilter}}
            class="workspace-groups-create-channel-modal__input"
            placeholder={{i18n
              "discourse_workspace_groups.auto_join_channels_filter_placeholder"
            }}
            {{on "input" this.updateAutoJoinChannelsFilter}}
          />
          <div class="workspace-groups-create-channel-modal__channel-list">
            {{#if this.filteredAutoJoinChannelOptions.length}}
              {{#each this.filteredAutoJoinChannelOptions as |channel|}}
                <label
                  class="workspace-groups-create-channel-modal__channel-option"
                >
                  <input
                    type="checkbox"
                    checked={{has this.selectedAutoJoinChannelIds channel.id}}
                    {{on "change" (fn this.toggleAutoJoinChannel channel.id)}}
                  />
                  <span>{{channel.name}}</span>
                </label>
              {{/each}}
            {{else}}
              <p class="workspace-groups-create-channel-modal__empty-state">
                {{i18n "discourse_workspace_groups.auto_join_channels_empty"}}
              </p>
            {{/if}}
          </div>
          <p class="workspace-groups-create-channel-modal__help">
            {{i18n "discourse_workspace_groups.auto_join_channels_help"}}
          </p>
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.saveWorkspace}}
          @label="discourse_workspace_groups.save_workspace"
          class="btn-primary"
          @disabled={{not this.canSave}}
        />
        <DButton @action={{this.cancel}} @label="cancel" class="btn-default" />
      </:footer>
    </DModal>
  </template>
}
