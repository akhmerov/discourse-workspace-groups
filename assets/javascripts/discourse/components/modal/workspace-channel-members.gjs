import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import UserChooser from "discourse/select-kit/components/user-chooser";
import { not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";

export default class WorkspaceChannelMembersModal extends Component {
  @tracked loadedChannel = null;
  @tracked members = [];
  @tracked selectedUsernames = [];
  @tracked loading = true;
  @tracked saving = false;

  constructor() {
    super(...arguments);
    this.loadAccess();
  }

  get workspace() {
    return this.args.model.workspace;
  }

  get category() {
    return this.args.model.category;
  }

  get channel() {
    return this.loadedChannel || this.args.model.channel;
  }

  get workspaceGroupName() {
    return this.workspace?.group_name;
  }

  get modalTitle() {
    return i18n("discourse_workspace_groups.channel_members_title", {
      name: this.channel?.name,
    });
  }

  get accessUrl() {
    return `/workspace-groups/workspaces/${this.category.id}/channels/${this.channel.id}/access`;
  }

  get excludedUsernames() {
    return this.members.map((member) => member.username);
  }

  get canAddMembers() {
    return Boolean(this.channel?.can_add_members);
  }

  get canSubmit() {
    return this.canAddMembers && !this.saving && this.selectedUsernames.length > 0;
  }

  applyAccessPayload(result) {
    this.loadedChannel = result.channel;
    this.members = result.members || [];
    this.args.model.onUpdate?.(result.channel);
  }

  @action
  async loadAccess() {
    this.loading = true;

    try {
      const result = await ajax(`${this.accessUrl}.json`);
      this.applyAccessPayload(result);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  updateSelectedUsernames(usernames) {
    this.selectedUsernames = usernames || [];
  }

  @action
  async addMembers() {
    if (!this.canSubmit) {
      return;
    }

    this.saving = true;

    try {
      const result = await ajax(`${this.accessUrl}.json`, {
        type: "POST",
        data: {
          usernames: this.selectedUsernames.join(","),
        },
      });

      this.selectedUsernames = [];
      this.applyAccessPayload(result);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async removeMember(member) {
    if (!member.can_remove || this.saving) {
      return;
    }

    this.saving = true;

    try {
      const result = await ajax(`${this.accessUrl}/${member.id}.json`, {
        type: "DELETE",
      });

      this.applyAccessPayload(result);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <DModal
      @title={{this.modalTitle}}
      @closeModal={{@closeModal}}
      @inline={{@inline}}
      class="workspace-groups-channel-members-modal"
    >
      <:body>
        {{#if this.loading}}
          <p class="workspace-groups-channel-members-modal__empty">
            {{i18n "loading"}}
          </p>
        {{else}}
          {{#if this.canAddMembers}}
            <div class="workspace-groups-channel-members-modal__add">
              <div class="workspace-groups-channel-members-modal__add-header">
                <span class="workspace-groups-create-channel-modal__label">
                  {{i18n "discourse_workspace_groups.add_channel_members"}}
                </span>
                <DButton
                  @action={{this.addMembers}}
                  @label="discourse_workspace_groups.add_channel_members"
                  @icon="user-plus"
                  class="btn-primary"
                  @disabled={{not this.canSubmit}}
                />
              </div>
              <label class="workspace-groups-create-channel-modal__field">
                <UserChooser
                  @value={{this.selectedUsernames}}
                  @onChange={{this.updateSelectedUsernames}}
                  @options={{hash
                    excludedUsernames=this.excludedUsernames
                    groupMembersOf=this.workspaceGroupName
                  }}
                />
              </label>
              <p class="workspace-groups-create-channel-modal__help">
                {{i18n "discourse_workspace_groups.add_channel_members_help"}}
              </p>
            </div>
          {{/if}}

          {{#if this.members.length}}
            <div class="workspace-groups-channel-members-modal__list">
              {{#each this.members as |member|}}
                <div class="workspace-groups-channel-members-modal__member">
                  <div class="workspace-groups-channel-members-modal__member-main">
                    {{dAvatar member imageSize="small"}}
                    <div class="workspace-groups-channel-members-modal__member-text">
                      <span class="workspace-groups-channel-members-modal__username">
                        {{member.username}}
                      </span>
                      {{#if member.name}}
                        <span class="workspace-groups-channel-members-modal__name">
                          {{member.name}}
                        </span>
                      {{/if}}
                    </div>
                  </div>

                  <div class="workspace-groups-channel-members-modal__member-actions">
                    {{#if member.owner}}
                      <span class="workspace-groups-channel-members-modal__badge">
                        {{i18n "discourse_workspace_groups.channel_member_owner"}}
                      </span>
                    {{/if}}
                    {{#if member.guest}}
                      <span class="workspace-groups-channel-members-modal__badge">
                        {{i18n "discourse_workspace_groups.channel_member_guest"}}
                      </span>
                    {{/if}}
                    {{#if member.can_remove}}
                      <DButton
                        @action={{fn this.removeMember member}}
                        @icon="trash-can"
                        @title="discourse_workspace_groups.remove_channel_member"
                        @ariaLabel="discourse_workspace_groups.remove_channel_member"
                        class="btn-danger btn-small"
                        @disabled={{this.saving}}
                      />
                    {{/if}}
                  </div>
                </div>
              {{/each}}
            </div>
          {{else}}
            <p class="workspace-groups-channel-members-modal__empty">
              {{i18n "discourse_workspace_groups.channel_members_empty"}}
            </p>
          {{/if}}
        {{/if}}
      </:body>
      <:footer>
        <DButton @action={{@closeModal}} @label="close" class="btn-default" />
      </:footer>
    </DModal>
  </template>
}
