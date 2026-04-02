import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { ajax } from "discourse/lib/ajax";

export default class DiscoveryWorkspaceOverviewController extends Controller {
  @service composer;
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

  updateChannel(channel, payload) {
    Object.entries(payload).forEach(([key, value]) => {
      channel[key] = value;
    });
  }

  @action
  createTopic() {
    this.composer.openNewTopic({
      category: this.createTopicTargetCategory,
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
}
