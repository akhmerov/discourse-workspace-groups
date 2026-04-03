import { withPluginApi } from "discourse/lib/plugin-api";
import WorkspaceTeamSidebarBlock from "../blocks/workspace-team-sidebar";

export default {
  name: "register-workspace-team-sidebar-block",
  before: "freeze-block-registry",

  initialize() {
    withPluginApi((api) => {
      api.registerBlock(WorkspaceTeamSidebarBlock);
    });
  },
};
