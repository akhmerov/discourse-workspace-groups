import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input } from "@ember/component";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default class ManageWorkspaceChannelAccessModal extends Component {
  @tracked usernames = "";
  @tracked members = [];
  @tracked loading = true;
  @tracked saving = false;
  @tracked removingUserId = null;

  constructor(owner, args) {
    super(owner, args);
    void this.loadMembers();
  }

  get category() {
    return this.args.model.category;
  }

  get channel() {
    return this.args.model.channel;
  }

  get modalTitle() {
    return i18n("discourse_workspace_groups.manage_access_title", {
      name: this.channel.name,
    });
  }

  get addDisabled() {
    return this.loading || this.saving || this.usernames.trim().length === 0;
  }

  get membersLoaded() {
    return !this.loading;
  }

  updateChannel(channel) {
    this.args.model.onChannelUpdate?.(channel);
  }

  @action
  async loadMembers() {
    this.loading = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.category.id}/channels/${this.channel.id}/access`
      );

      this.members = result.members || [];
      this.updateChannel(result.channel);
    } catch (error) {
      popupAjaxError(error);
      this.args.closeModal();
    } finally {
      this.loading = false;
    }
  }

  @action
  async addMembers() {
    if (this.addDisabled) {
      return;
    }

    this.saving = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.category.id}/channels/${this.channel.id}/access`,
        {
          type: "POST",
          data: {
            usernames: this.usernames.trim(),
          },
        }
      );

      this.members = result.members || [];
      this.usernames = "";
      this.updateChannel(result.channel);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async removeMember(member) {
    this.removingUserId = member.id;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.category.id}/channels/${this.channel.id}/access/${member.id}`,
        {
          type: "DELETE",
        }
      );

      this.members = result.members || [];
      this.updateChannel(result.channel);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.removingUserId = null;
    }
  }

  @action
  close() {
    this.args.closeModal();
  }

  <template>
    <DModal
      @title={{this.modalTitle}}
      @closeModal={{@closeModal}}
      @inline={{@inline}}
      class="workspace-groups-channel-access-modal"
    >
      <:body>
        <div class="workspace-groups-channel-access-modal__composer">
          <label class="workspace-groups-channel-access-modal__field">
            <span class="workspace-groups-channel-access-modal__label">
              {{i18n "discourse_workspace_groups.manage_access_add_label"}}
            </span>
            <Input
              @value={{this.usernames}}
              class="workspace-groups-channel-access-modal__input"
              autofocus={{true}}
            />
          </label>

          <p class="workspace-groups-channel-access-modal__help">
            {{i18n "discourse_workspace_groups.manage_access_add_help"}}
          </p>

          <DButton
            @action={{this.addMembers}}
            @label="discourse_workspace_groups.add_people"
            class="btn-primary btn-small workspace-groups-channel-access-modal__add-button"
            @disabled={{this.addDisabled}}
          />
        </div>

        {{#if this.membersLoaded}}
          <div class="workspace-groups-channel-access-modal__members">
            {{#each this.members as |member|}}
              <div class="workspace-groups-channel-access-modal__member">
                <div class="workspace-groups-channel-access-modal__member-copy">
                  <div class="workspace-groups-channel-access-modal__member-name">
                    @{{member.username}}
                  </div>

                  {{#if member.name}}
                    <div class="workspace-groups-channel-access-modal__member-full-name">
                      {{member.name}}
                    </div>
                  {{/if}}

                  <div class="workspace-groups-channel-access-modal__member-badges">
                    {{#if member.owner}}
                      <span class="workspace-groups-channel-access-modal__badge">
                        {{i18n "discourse_workspace_groups.owner"}}
                      </span>
                    {{/if}}

                    {{#if member.guest}}
                      <span class="workspace-groups-channel-access-modal__badge">
                        {{i18n "discourse_workspace_groups.guest_member"}}
                      </span>
                    {{else}}
                      <span class="workspace-groups-channel-access-modal__badge">
                        {{i18n "discourse_workspace_groups.team_member"}}
                      </span>
                    {{/if}}
                  </div>
                </div>

                {{#if member.can_remove}}
                  <DButton
                    @action={{fn this.removeMember member}}
                    @label="remove"
                    class="btn-default btn-small workspace-groups-channel-access-modal__remove-button"
                    @disabled={{eq member.id this.removingUserId}}
                  />
                {{/if}}
              </div>
            {{/each}}
          </div>
        {{else}}
          <p class="workspace-groups-channel-access-modal__loading">
            {{i18n "loading"}}
          </p>
        {{/if}}
      </:body>
      <:footer>
        <DButton @action={{this.close}} @label="close" class="btn-default" />
      </:footer>
    </DModal>
  </template>
}
