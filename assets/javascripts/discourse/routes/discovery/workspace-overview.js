import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import Category from "discourse/models/category";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class DiscoveryWorkspaceOverviewRoute extends DiscourseRoute {
  @service router;
  @service site;

  async model(params) {
    const category = this.site.lazy_load_categories
      ? await Category.asyncFindBySlugPathWithID(
          params.category_slug_path_with_id
        )
      : Category.findBySlugPathWithID(params.category_slug_path_with_id);

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
      channels: result.channels || [],
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
