import Controller from "@ember/controller";
import { trackedObject } from "@ember/reactive/collections";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import CreateWorkspaceChannelModal from "../../components/modal/create-workspace-channel";
import WorkspaceChannelSettingsModal from "../../components/modal/workspace-channel-settings";
import WorkspaceSettingsModal from "../../components/modal/workspace-settings";

export default class DiscoveryWorkspaceOverviewController extends Controller {
  @service chat;
  @service chatChannelsManager;
  @service composer;
  @service dialog;
  @service modal;
  @service siteSettings;

  get subcategoryWithPermission() {
    if (this.siteSettings.default_subcategory_on_read_only_category) {
      return this.model.category?.subcategoryWithCreateTopicPermission;
    }
  }

  get createTopicTargetCategory() {
    const { category } = this.model;

    if (category?.canCreateTopic) {
      return category;
    }

    return this.subcategoryWithPermission ?? category;
  }

  get createTopicDisabled() {
    return !this.model.category?.canCreateTopic && !this.subcategoryWithPermission;
  }

  get canCreateChannel() {
    return (
      this.model.workspace?.can_create_channel ??
      this.model.category?.workspace_can_create_channel
    );
  }

  get teamName() {
    return this.model.workspace?.name || this.model.category?.name;
  }

  get teamVisibilityIcon() {
    return this.model.workspace?.public_read ? "globe" : "lock";
  }

  get teamVisibilityLabel() {
    return i18n(
      this.model.workspace?.public_read
        ? "discourse_workspace_groups.visibility_public"
        : "discourse_workspace_groups.visibility_private"
    );
  }

  get teamMemberCount() {
    return this.model.workspace?.member_count || 0;
  }

  get teamMembersUrl() {
    return this.model.workspace?.members_url;
  }

  get teamCanViewMembers() {
    return Boolean(this.model.workspace?.can_view_members && this.teamMembersUrl);
  }

  get canManageWorkspace() {
    return Boolean(this.model.workspace?.can_manage);
  }

  get teamAboutCooked() {
    return this.model.workspace?.about_cooked;
  }

  get activeChannels() {
    return this.model.activeChannels || [];
  }

  get archivedChannels() {
    return this.model.archivedChannels || [];
  }

  get archivedChannelCount() {
    return this.model.archivedChannelCount || 0;
  }

  get hasArchivedChannels() {
    return this.archivedChannelCount > 0;
  }

  updateChannel(channel, payload) {
    Object.entries(payload).forEach(([key, value]) => {
      channel[key] = value;
    });
  }

  applyChannelPayload(channel, payload) {
    const wasArchived = channel.archived;

    this.updateChannel(channel, payload);

    if (!payload.visible) {
      if (wasArchived) {
        this.model.archivedChannelCount = Math.max(
          0,
          this.model.archivedChannelCount - 1
        );
      }

      this.removeChannelFromList(this.activeChannels, channel);
      this.removeChannelFromList(this.archivedChannels, channel);
      return;
    }

    if (!wasArchived && payload.archived) {
      this.removeChannelFromList(this.activeChannels, channel);

      if (this.model.archivedChannelsLoaded) {
        this.addChannelToList(this.archivedChannels, channel);
      }

      this.model.archivedChannelCount += 1;
      return;
    }

    if (wasArchived && !payload.archived) {
      this.removeChannelFromList(this.archivedChannels, channel);
      this.addChannelToList(this.activeChannels, channel);
      this.model.archivedChannelCount = Math.max(
        0,
        this.model.archivedChannelCount - 1
      );
    }
  }

  trackChannel(channel) {
    return trackedObject({ ...channel, is_pending: false });
  }

  removeChannelFromList(list, channel) {
    const index = list.findIndex((entry) => entry.id === channel.id);

    if (index > -1) {
      list.splice(index, 1);
    }
  }

  addChannelToList(list, channel) {
    if (!list.some((entry) => entry.id === channel.id)) {
      list.push(channel);
    }
  }

  storeChatChannel(channel) {
    if (!channel?.chat_channel) {
      return;
    }

    this.chatChannelsManager.store(channel.chat_channel, {
      replace: true,
    });
  }

  async syncJoinedChatChannel(channel) {
    if (channel?.chat_channel) {
      const storedChannel = this.chatChannelsManager.store(channel.chat_channel, {
        replace: true,
      });

      await this.chatChannelsManager.follow(storedChannel);
      return;
    }

    if (!channel?.chat_channel_id) {
      return;
    }

    await this.chat.loadChannels();
    await this.chatChannelsManager.find(channel.chat_channel_id);
  }

  removeJoinedChatChannel(channel) {
    if (!channel?.chat_channel_id) {
      return;
    }

    const joinedChannel = this.chatChannelsManager.channels.find(
      (chatChannel) => chatChannel.id === channel.chat_channel_id
    );

    if (joinedChannel) {
      this.chatChannelsManager.remove(joinedChannel);
    }
  }

  applyWorkspacePayload(payload) {
    Object.entries(payload).forEach(([key, value]) => {
      this.model.workspace[key] = value;
    });
  }

  async confirmPrivateChannelLeave(channel) {
    if (channel?.visibility !== "private") {
      return true;
    }

    return await this.dialog.confirm({
      message: i18n("discourse_workspace_groups.leave_private_channel_message", {
        channel_name: channel.name,
      }),
      confirmButtonLabel:
        "discourse_workspace_groups.leave_private_channel_confirm",
      cancelButtonLabel: "cancel",
    });
  }

  @action
  createTopic() {
    this.composer.openNewTopic({
      category: this.createTopicTargetCategory,
    });
  }

  @action
  openCreateChannelModal() {
    this.modal.show(CreateWorkspaceChannelModal, {
      model: {
        category: this.model.category,
        workspace: this.model.workspace,
      },
    });
  }

  @action
  openWorkspaceSettingsModal() {
    this.modal.show(WorkspaceSettingsModal, {
      model: {
        workspace: this.model.workspace,
        onUpdate: async (updatedWorkspace) => {
          this.applyWorkspacePayload(updatedWorkspace);
        },
      },
    });
  }

  @action
  openChannelSettingsModal(channel) {
    this.modal.show(WorkspaceChannelSettingsModal, {
      model: {
        category: this.model.category,
        workspace: this.model.workspace,
        channel,
        onUpdate: async (updatedChannel) => {
          const previousChatChannelId = channel.chat_channel_id;
          this.applyChannelPayload(channel, updatedChannel);
          if (updatedChannel.chat_channel) {
            this.storeChatChannel(updatedChannel);
          } else if (previousChatChannelId) {
            this.removeJoinedChatChannel({
              chat_channel_id: previousChatChannelId,
            });
          }
        },
      },
    });
  }

  @action
  async joinChannel(channel) {
    channel.is_pending = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.model.category.id}/channels/${channel.id}/membership`,
        {
          type: "POST",
        }
      );

      this.applyChannelPayload(channel, result.channel);
      await this.syncJoinedChatChannel(result.channel);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      channel.is_pending = false;
    }
  }

  @action
  async leaveChannel(channel) {
    if (!(await this.confirmPrivateChannelLeave(channel))) {
      return;
    }

    channel.is_pending = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.model.category.id}/channels/${channel.id}/membership`,
        {
          type: "DELETE",
        }
      );

      this.removeJoinedChatChannel(result.channel);
      this.applyChannelPayload(channel, result.channel);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      channel.is_pending = false;
    }
  }

  @action
  async archiveChannel(channel) {
    channel.is_pending = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.model.category.id}/channels/${channel.id}/archive`,
        {
          type: "POST",
        }
      );

      this.applyChannelPayload(channel, result.channel);
      this.storeChatChannel(result.channel);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      channel.is_pending = false;
    }
  }

  @action
  async unarchiveChannel(channel) {
    channel.is_pending = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.model.category.id}/channels/${channel.id}/archive`,
        {
          type: "DELETE",
        }
      );

      this.applyChannelPayload(channel, result.channel);
      this.storeChatChannel(result.channel);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      channel.is_pending = false;
    }
  }

  @action
  async loadArchivedChannels(event) {
    if (
      !event?.target?.open ||
      this.model.archivedChannelsLoaded ||
      this.model.archivedChannelsLoading ||
      this.archivedChannelCount === 0
    ) {
      return;
    }

    this.model.archivedChannelsLoading = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.model.category.id}/archived-channels.json`
      );

      this.model.archivedChannels.splice(
        0,
        this.model.archivedChannels.length,
        ...(result.channels || []).map((channel) => this.trackChannel(channel))
      );
      this.model.archivedChannelsLoaded = true;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.model.archivedChannelsLoading = false;
    }
  }
}
