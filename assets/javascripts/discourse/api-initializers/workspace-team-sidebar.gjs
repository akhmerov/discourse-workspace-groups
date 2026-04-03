import { apiInitializer } from "discourse/lib/api";

export const WORKSPACE_TEAM_SIDEBAR_BLOCK =
  "discourse-workspace-groups:workspace-team-sidebar";

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  api.renderBlocks("sidebar-blocks", [
    { block: WORKSPACE_TEAM_SIDEBAR_BLOCK },
  ]);
});
