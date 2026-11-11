import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import CreateWorkspaceChannelModal from "./modal/create-workspace-channel.gjs";

// Site categories are serialized without a user scope, so per-user permissions
// come from the workspace payload, which is only needed while a team is empty.
export default class WorkspaceTeamSidebarEmpty extends Component {
  @service modal;

  @tracked workspacePayload = null;

  get canCreateChannel() {
    return (
      Number(this.workspacePayload?.id) === Number(this.args.category?.id) &&
      !!this.workspacePayload?.can_create_channel
    );
  }

  @action
  async loadWorkspace() {
    const workspaceId = this.args.category?.id;

    if (!workspaceId) {
      return;
    }

    try {
      const result = await ajax(`/workspace-groups/workspaces/${workspaceId}.json`);

      if (
        !this.isDestroying &&
        Number(this.args.category?.id) === Number(workspaceId)
      ) {
        this.workspacePayload = result.workspace;
      }
    } catch {
      // Without a payload the sidebar keeps the message and omits the action.
    }
  }

  @action
  openCreateChannelModal() {
    this.modal.show(CreateWorkspaceChannelModal, {
      model: {
        category: this.args.category,
        workspace: this.workspacePayload,
      },
    });
  }

  <template>
    <li
      class="workspace-team-sidebar__empty"
      {{didInsert this.loadWorkspace}}
      {{didUpdate this.loadWorkspace @category.id}}
    >
      {{i18n "discourse_workspace_groups.no_channels_yet"}}
    </li>
    {{#if this.canCreateChannel}}
      <li class="workspace-team-sidebar__empty-action">
        <button
          class="btn btn-default btn-small workspace-team-sidebar__create-channel"
          type="button"
          {{on "click" this.openCreateChannelModal}}
        >
          {{dIcon "plus"}}
          <span>{{i18n "discourse_workspace_groups.create_channel_title"}}</span>
        </button>
      </li>
    {{/if}}
  </template>
}
