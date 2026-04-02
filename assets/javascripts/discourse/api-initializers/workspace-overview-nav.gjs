import { apiInitializer } from "discourse/lib/api";
import Category from "discourse/models/category";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  api.addNavigationBarItem({
    name: "workspace-overview",
    displayName: i18n("discourse_workspace_groups.overview"),
    before: "latest",
    customFilter(category) {
      return category?.workspace_kind === "workspace";
    },
    customHref(category) {
      return `/c/${Category.slugFor(category)}/${category.id}/overview`;
    },
    forceActive(_category, _args, router) {
      return router.currentRouteName === "discovery.workspaceOverview";
    },
  });
});
