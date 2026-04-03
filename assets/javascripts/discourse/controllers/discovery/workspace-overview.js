import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { ajax } from "discourse/lib/ajax";
import CreateWorkspaceChannelModal from "../../components/modal/create-workspace-channel";

export default class DiscoveryWorkspaceOverviewController extends Controller {
  @service chat;
  @service chatChannelsManager;
  @service composer;
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

  get activeChannels() {
    return (this.model.channels || []).filter((channel) => !channel.archived);
  }

  get archivedChannels() {
    return (this.model.channels || []).filter((channel) => channel.archived);
  }

  updateChannel(channel, payload) {
    Object.entries(payload).forEach(([key, value]) => {
      channel[key] = value;
    });
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

  @action
  createTopic() {
    this.composer.openNewTopic({
      category: this.createTopicTargetCategory,
    });
  }

  @action
  openCreateChannelModal() {
    this.modal.show(CreateWorkspaceChannelModal, {
      model: { category: this.model.category },
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

      this.updateChannel(channel, result.channel);
      await this.syncJoinedChatChannel(result.channel);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      channel.is_pending = false;
    }
  }

  @action
  async leaveChannel(channel) {
    channel.is_pending = true;

    try {
      const result = await ajax(
        `/workspace-groups/workspaces/${this.model.category.id}/channels/${channel.id}/membership`,
        {
          type: "DELETE",
        }
      );

      this.removeJoinedChatChannel(result.channel);

      if (!result.channel.visible) {
        const index = this.model.channels.indexOf(channel);
        if (index > -1) {
          this.model.channels.splice(index, 1);
        }
        return;
      }

      this.updateChannel(channel, result.channel);
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

      this.updateChannel(channel, result.channel);
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

      this.updateChannel(channel, result.channel);
      this.storeChatChannel(result.channel);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      channel.is_pending = false;
    }
  }
}
