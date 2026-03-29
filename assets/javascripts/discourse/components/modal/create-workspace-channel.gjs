import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import DToggleSwitch from "discourse/components/d-toggle-switch";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";

export default class CreateWorkspaceChannelModal extends Component {
  @tracked name = "";
  @tracked description = "";
  @tracked isPrivate = false;
  @tracked usernames = "";
  @tracked saving = false;

  get category() {
    return this.args.model.category;
  }

  get modalTitle() {
    return i18n("discourse_workspace_groups.create_channel_title");
  }

  get canCreate() {
    return !this.saving && this.name.trim().length > 0;
  }

  @action
  togglePrivate() {
    this.isPrivate = !this.isPrivate;
  }

  @action
  async createChannel() {
    if (this.saving || !this.name.trim()) {
      return;
    }

    this.saving = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.category.id}/channels`,
        {
          type: "POST",
          data: {
            name: this.name.trim(),
            description: this.description.trim(),
            visibility: this.isPrivate ? "private" : "public",
            usernames: this.usernames.trim(),
          },
        }
      );

      this.args.closeModal();
      DiscourseURL.routeTo(result.category_url);
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
      class="workspace-groups-create-channel-modal"
    >
      <:body>
        <label class="workspace-groups-create-channel-modal__field">
          <span class="workspace-groups-create-channel-modal__label">
            {{i18n "discourse_workspace_groups.channel_name"}}
          </span>
          <Input
            @value={{this.name}}
            class="workspace-groups-create-channel-modal__input"
            autofocus={{true}}
          />
        </label>

        <label class="workspace-groups-create-channel-modal__field">
          <span class="workspace-groups-create-channel-modal__label">
            {{i18n "discourse_workspace_groups.channel_description"}}
          </span>
          <Textarea
            @value={{this.description}}
            class="workspace-groups-create-channel-modal__textarea"
          />
        </label>

        <div class="workspace-groups-create-channel-modal__field">
          <DToggleSwitch
            @state={{this.isPrivate}}
            @label="discourse_workspace_groups.private_channel"
            {{on "click" this.togglePrivate}}
          />
          <p class="workspace-groups-create-channel-modal__help">
            {{i18n "discourse_workspace_groups.private_channel_help"}}
          </p>
        </div>

        {{#if this.isPrivate}}
          <label class="workspace-groups-create-channel-modal__field">
            <span class="workspace-groups-create-channel-modal__label">
              {{i18n "discourse_workspace_groups.private_members"}}
            </span>
            <Input
              @value={{this.usernames}}
              class="workspace-groups-create-channel-modal__input"
            />
            <p class="workspace-groups-create-channel-modal__help">
              {{i18n "discourse_workspace_groups.private_members_help"}}
            </p>
          </label>
        {{/if}}
      </:body>
      <:footer>
        <DButton
          @action={{this.createChannel}}
          @label="discourse_workspace_groups.create"
          class="btn-primary"
          @disabled={{not this.canCreate}}
        />
        <DButton @action={{this.cancel}} @label="cancel" class="btn-default" />
      </:footer>
    </DModal>
  </template>
}
