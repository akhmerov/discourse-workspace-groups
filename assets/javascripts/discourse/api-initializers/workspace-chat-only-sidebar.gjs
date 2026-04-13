import { apiInitializer } from "discourse/lib/api";

function showCategoryInCoreSidebar(category) {
  return category?.workspace_channel_mode !== "chat_only";
}

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  api.modifyClass(
    "component:sidebar/user/categories-section",
    (Superclass) =>
      class extends Superclass {
        get categories() {
          return super.categories.filter(showCategoryInCoreSidebar);
        }
      }
  );
});
