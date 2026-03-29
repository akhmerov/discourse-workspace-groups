import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import CreateWorkspaceChannelModal from "../../components/modal/create-workspace-channel";

export default class WorkspaceChannelActions extends Component {
  @service modal;

  static shouldRender(outletArgs) {
    return (
      outletArgs.category?.workspace_can_enable ||
      (
        outletArgs.category?.workspace_kind === "workspace" &&
          outletArgs.category?.workspace_can_create_channel
      )
    );
  }

  get category() {
    return this.args.outletArgs.category;
  }

  get canEnableWorkspace() {
    return this.category?.workspace_can_enable;
  }

  get canCreateChannel() {
    return (
      this.category?.workspace_kind === "workspace" &&
      this.category?.workspace_can_create_channel
    );
  }

  @action
  async enableWorkspace() {
    try {
      await ajax(`/workspace-groups/workspaces/${this.category.id}/enable`, {
        type: "POST",
      });
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  showCreateChannelModal() {
    this.modal.show(CreateWorkspaceChannelModal, { model: { category: this.category } });
  }

  <template>
    <div class="workspace-groups-actions">
      {{#if this.canEnableWorkspace}}
        <DButton
          @action={{this.enableWorkspace}}
          @icon="layer-group"
          @label="discourse_workspace_groups.enable_workspace"
          class="btn-small btn-default workspace-groups-actions__button"
        />
      {{/if}}

      {{#if this.canCreateChannel}}
        <DButton
          @action={{this.showCreateChannelModal}}
          @icon="layer-group"
          @label="discourse_workspace_groups.create_channel"
          class="btn-small btn-default workspace-groups-actions__button"
        />
      {{/if}}
    </div>
  </template>
}
