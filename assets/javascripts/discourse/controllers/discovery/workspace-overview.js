import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";

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

  @action
  createTopic() {
    this.composer.openNewTopic({
      category: this.createTopicTargetCategory,
    });
  }
}
