import { apiInitializer } from "discourse/lib/api";
import Category from "discourse/models/category";

export function workspaceOverviewRouteParam(category) {
  return `${Category.slugFor(category)}/${category.id}`;
}

export function shouldRedirectWorkspaceCategory(category) {
  return category?.workspace_kind === "workspace";
}

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  api.modifyClass(
    "route:discovery.category",
    (Superclass) =>
      class extends Superclass {
        redirect(model, transition) {
          super.redirect?.(model, transition);

          const category = model?.category;
          if (!shouldRedirectWorkspaceCategory(category)) {
            return;
          }

          this.router.replaceWith(
            "discovery.workspaceOverview",
            workspaceOverviewRouteParam(category)
          );
        }
      }
  );
});
