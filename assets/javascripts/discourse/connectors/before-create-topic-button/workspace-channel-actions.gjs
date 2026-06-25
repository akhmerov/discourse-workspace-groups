import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import WorkspaceChannelMembersModal from "../../components/modal/workspace-channel-members";
import WorkspaceChannelSettingsModal from "../../components/modal/workspace-channel-settings";

export default class WorkspaceChannelActions extends Component {
  static shouldRender(outletArgs) {
    return !!outletArgs.category;
  }

  @service modal;
  @service site;

  @tracked channel;
  @tracked loadKey;
  @tracked workspace;

  get category() {
    const outletCategory = this.args.outletArgs.category;
    const categoryId = outletCategory?.id;
    const categoriesById = this.site.categoriesById;

    return (
      categoriesById?.get?.(categoryId) ||
      categoriesById?.[categoryId] ||
      outletCategory
    );
  }

  get workspaceId() {
    return (
      this.category?.workspace_parent_category?.id ||
      this.category?.workspace_parent_category_id ||
      this.category?.parent_category_id
    );
  }

  get isWorkspaceChannelCategory() {
    return (
      this.category?.workspace_kind === "channel" ||
      !!this.category?.workspace_channel_mode
    );
  }

  get chatPath() {
    if (
      !this.channel ||
      this.channel.mode === "category_only" ||
      !this.channel.chat_channel_id
    ) {
      return null;
    }

    return `/chat/c/${this.channel.chat_channel?.slug || "-"}/${this.channel.chat_channel_id}`;
  }

  get canViewMembers() {
    return !!this.channel?.can_view_members;
  }

  get canSeeSettings() {
    return !!(
      this.channel &&
      (this.workspace?.can_manage ||
        this.channel.can_archive ||
        this.channel.can_unarchive)
    );
  }

  get canEnableWorkspace() {
    return this.category?.workspace_can_enable;
  }

  @action
  async loadChannel() {
    const categoryId = this.category?.id;

    if (!this.isWorkspaceChannelCategory || !this.workspaceId || !categoryId) {
      this.channel = null;
      this.workspace = null;
      this.loadKey = null;
      return;
    }

    const loadKey = `${this.workspaceId}:${categoryId}`;
    if (this.loadKey === loadKey) {
      return;
    }

    this.loadKey = loadKey;
    this.channel = null;
    this.workspace = null;

    try {
      const response = await fetch(
        `/workspace-groups/workspaces/${this.workspaceId}.json`,
        { headers: { "X-Requested-With": "XMLHttpRequest" } }
      );
      if (!response.ok) {
        throw new Error(`Workspace metadata returned HTTP ${response.status}`);
      }
      const result = await response.json();

      if (this.isDestroying || this.isDestroyed || this.loadKey !== loadKey) {
        return;
      }

      this.workspace = result.workspace;
      this.channel =
        result.channels?.find((candidate) => candidate.id === categoryId) ||
        null;
    } catch (error) {
      if (this.loadKey === loadKey) {
        this.loadKey = null;
      }

      // Keep category rendering non-fatal; failed workspace metadata should not
      // break the normal category header.
      // eslint-disable-next-line no-console
      console.warn("Failed to load workspace channel actions", error);
    }
  }

  @action
  openSettings() {
    if (!this.channel || !this.workspaceId) {
      return;
    }

    this.modal.show(WorkspaceChannelSettingsModal, {
      model: {
        category: { id: this.workspaceId },
        workspace: this.workspace,
        channel: this.channel,
        onOpenMembers: this.openMembers,
        onUpdate: async (updatedChannel) => {
          this.channel = { ...this.channel, ...updatedChannel };
        },
      },
    });
  }

  @action
  openMembers() {
    if (!this.channel || !this.workspaceId) {
      return;
    }

    this.modal.show(WorkspaceChannelMembersModal, {
      model: {
        category: { id: this.workspaceId },
        workspace: this.workspace,
        channel: this.channel,
        onUpdate: async (updatedChannel) => {
          this.channel = { ...this.channel, ...updatedChannel };
        },
      },
    });
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
    <div class="workspace-groups-actions" {{didInsert this.loadChannel}}>
      {{#if this.chatPath}}
        <a
          href={{this.chatPath}}
          class="btn no-text btn-icon btn-default workspace-groups-actions__button workspace-groups-actions__chat"
          title="Chat channel"
          aria-label="Chat channel"
        >
          {{dIcon "d-chat"}}
          <span aria-hidden="true">
            &#8203;
          </span>
        </a>
      {{/if}}

      {{#if this.canViewMembers}}
        <DButton
          @action={{this.openMembers}}
          @icon="user"
          @title="discourse_workspace_groups.channel_members"
          @ariaLabel="discourse_workspace_groups.channel_members"
          class="btn-default workspace-groups-actions__button workspace-groups-actions__members"
        />
      {{/if}}

      {{#if this.canSeeSettings}}
        <DButton
          @action={{this.openSettings}}
          @icon="wrench"
          @title="discourse_workspace_groups.channel_settings"
          @ariaLabel="discourse_workspace_groups.channel_settings"
          class="btn-default workspace-groups-actions__button workspace-groups-actions__settings"
        />
      {{/if}}

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
