import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class WorkspaceChannelActions extends Component {
  @service site;

  static shouldRender(outletArgs) {
    return !!outletArgs.category;
  }

  get category() {
    const categoryId = this.args.outletArgs.category?.id;
    return this.site.categoriesById?.get(categoryId) || this.args.outletArgs.category;
  }

  get canEnableWorkspace() {
    return this.category?.workspace_can_enable;
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
  <template>
    <div class="workspace-groups-actions">
      {{#if this.canEnableWorkspace}}
        <DButton
          @action={{this.enableWorkspace}}
          @icon="plus"
          @title="discourse_workspace_groups.enable_workspace"
          @ariaLabel="discourse_workspace_groups.enable_workspace"
          class="btn-default workspace-groups-actions__button"
        />
      {{/if}}
    </div>
  </template>
}
