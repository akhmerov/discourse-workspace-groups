import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import WorkspaceChannelOrderRow from "../workspace-channel-order-row";

export default class ReorderWorkspaceChannelsModal extends Component {
  @tracked changed = false;
  @tracked isSaving = false;
  @tracked orderedChannels = [];

  draggedChannel = null;

  constructor() {
    super(...arguments);
    this.orderedChannels = [...(this.args.model?.channels || [])];
  }

  get saveDisabled() {
    return !this.changed || this.isSaving;
  }

  @action
  setDraggedChannel(channel) {
    this.draggedChannel = channel;
  }

  @action
  reorder(targetChannel, above) {
    if (this.draggedChannel?.id === targetChannel.id) {
      return;
    }

    const channels = [...this.orderedChannels];
    const draggedIndex = channels.findIndex(
      (channel) => channel.id === this.draggedChannel?.id
    );
    const targetIndex = channels.findIndex(
      (channel) => channel.id === targetChannel.id
    );

    if (draggedIndex < 0 || targetIndex < 0) {
      return;
    }

    const [draggedChannel] = channels.splice(draggedIndex, 1);
    let insertionIndex = targetIndex;

    if (draggedIndex < targetIndex) {
      insertionIndex -= 1;
    }

    if (!above) {
      insertionIndex += 1;
    }

    channels.splice(insertionIndex, 0, draggedChannel);
    this.orderedChannels = channels;
    this.changed = true;
  }

  @action
  async save() {
    this.isSaving = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.args.model.workspaceId}/reorder-channels`,
        {
          type: "PUT",
          data: {
            channel_ids: this.orderedChannels.map((channel) => channel.id),
          },
        }
      );

      await this.args.model.onReorder?.(result.channels || []);
      this.args.closeModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSaving = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "discourse_workspace_groups.reorder_channels_title"}}
      @closeModal={{@closeModal}}
      class="workspace-groups-reorder-channels-modal"
    >
      <:body>
        <p class="workspace-groups-reorder-channels-modal__help">
          {{i18n "discourse_workspace_groups.reorder_channels_help"}}
        </p>

        <div class="workspace-groups-reorder-channels-modal__list">
          {{#each this.orderedChannels as |channel|}}
            <WorkspaceChannelOrderRow
              @channel={{channel}}
              @setDraggedChannelCallback={{this.setDraggedChannel}}
              @reorderCallback={{this.reorder}}
            />
          {{/each}}
        </div>
      </:body>

      <:footer>
        <DButton
          @action={{this.save}}
          @label="discourse_workspace_groups.save_channel_order"
          @disabled={{this.saveDisabled}}
          class="btn-primary"
        />

        <DButton
          @action={{@closeModal}}
          @label="cancel"
          class="btn-default"
        />
      </:footer>
    </DModal>
  </template>
}
