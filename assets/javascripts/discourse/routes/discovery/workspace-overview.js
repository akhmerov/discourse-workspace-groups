import { trackedArray, trackedObject } from "@ember/reactive/collections";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import Category from "discourse/models/category";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class DiscoveryWorkspaceOverviewRoute extends DiscourseRoute {
  @service router;

  async model(params) {
    let category = Category.findBySlugPathWithID(params.category_slug_path_with_id);

    if (!category) {
      try {
        category = await Category.asyncFindBySlugPathWithID(
          params.category_slug_path_with_id
        );
      } catch {
        category = null;
      }
    }

    if (!category) {
      this.router.replaceWith("/404");
      return;
    }

    const workspace =
      category.workspace_kind === "workspace"
        ? category
        : category.workspace_parent_category;

    if (workspace?.workspace_kind !== "workspace") {
      this.router.replaceWith(category.url);
      return;
    }

    if (workspace?.id !== category.id) {
      this.router.replaceWith(
        "discovery.workspaceOverview",
        `${Category.slugFor(workspace)}/${workspace.id}`
      );
      return;
    }

    const result = await ajax(`/workspace-groups/workspaces/${workspace.id}.json`);

    return {
      category: workspace,
      workspace: trackedObject(result.workspace || {}),
      channels: trackedArray(
        (result.channels || []).map((channel) =>
          trackedObject({ ...channel, is_pending: false })
        )
      ),
      filterType: "workspace-overview",
      noSubcategories: false,
    };
  }

  titleToken() {
    const category = this.currentModel?.category;

    if (!category) {
      return;
    }

    return i18n("discourse_workspace_groups.overview_title", {
      name: category.displayName,
    });
  }
}
