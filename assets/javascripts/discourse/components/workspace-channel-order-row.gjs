import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import discourseLater from "discourse/lib/later";
import { i18n } from "discourse-i18n";

export default class WorkspaceChannelOrderRow extends Component {
  @tracked dragCssClass;
  dragCount = 0;

  get visibilityIcon() {
    return this.args.channel.visibility === "private" ? "lock" : "globe";
  }

  get visibilityLabel() {
    return i18n(
      this.args.channel.visibility === "private"
        ? "discourse_workspace_groups.visibility_private"
        : "discourse_workspace_groups.visibility_public"
    );
  }

  isAboveElement(event) {
    event.preventDefault();
    const target = event.currentTarget;
    const domRect = target.getBoundingClientRect();
    return event.offsetY < domRect.height / 2;
  }

  @action
  dragHasStarted(event) {
    event.dataTransfer.effectAllowed = "move";
    this.args.setDraggedChannelCallback(this.args.channel);
    this.dragCssClass = "dragging";
  }

  @action
  dragOver(event) {
    event.preventDefault();

    if (this.dragCssClass === "dragging") {
      return;
    }

    this.dragCssClass = this.isAboveElement(event) ? "drag-above" : "drag-below";
  }

  @action
  dragEnter() {
    this.dragCount++;
  }

  @action
  dragLeave() {
    this.dragCount--;

    if (
      this.dragCount === 0 &&
      (this.dragCssClass === "drag-above" || this.dragCssClass === "drag-below")
    ) {
      discourseLater(() => {
        this.dragCssClass = null;
      }, 10);
    }
  }

  @action
  dropItem(event) {
    event.stopPropagation();
    this.dragCount = 0;
    this.args.reorderCallback(this.args.channel, this.isAboveElement(event));
    this.dragCssClass = null;
  }

  @action
  dragEnd() {
    this.dragCount = 0;
    this.dragCssClass = null;
  }

  <template>
    <div
      {{on "dragstart" this.dragHasStarted}}
      {{on "dragover" this.dragOver}}
      {{on "dragenter" this.dragEnter}}
      {{on "dragleave" this.dragLeave}}
      {{on "dragend" this.dragEnd}}
      {{on "drop" this.dropItem}}
      draggable="true"
      class={{concatClass
        "workspace-groups-reorder-channels-modal__row"
        this.dragCssClass
      }}
    >
      <span class="workspace-groups-reorder-channels-modal__grip" aria-hidden="true">
        {{icon "grip-lines"}}
      </span>

      <div class="workspace-groups-reorder-channels-modal__row-copy">
        <span class="workspace-groups-reorder-channels-modal__row-name">
          {{@channel.name}}
        </span>
        <span
          class="workspace-groups-reorder-channels-modal__row-meta"
          title={{this.visibilityLabel}}
          aria-label={{this.visibilityLabel}}
        >
          {{icon this.visibilityIcon}}
          <span>{{this.visibilityLabel}}</span>
        </span>
      </div>
    </div>
  </template>
}
