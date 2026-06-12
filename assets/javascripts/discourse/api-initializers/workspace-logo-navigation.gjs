import { apiInitializer } from "discourse/lib/api";
import DiscourseURL from "discourse/lib/url";
import {
  currentWorkspaceCategory,
  memberWorkspaceCategories,
  workspaceOverviewPath,
} from "../lib/workspace-team-sidebar-state";

const WORKSPACE_FOCUS_KEY = "workspace-groups:focused-workspace-id";

function focusedWorkspaceId() {
  try {
    return Number(sessionStorage.getItem(WORKSPACE_FOCUS_KEY));
  } catch {
    return null;
  }
}

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  const router = api.container.lookup("service:router");

  function services() {
    return {
      chat: api.container.lookup("service:chat"),
      chatChannelsManager: api.container.lookup("service:chat-channels-manager"),
      currentUser: api.container.lookup("service:current-user"),
      router,
      site: api.container.lookup("service:site"),
      siteSettings,
      topicCategory:
        router.currentRouteName?.startsWith("topic.")
          ? api.container.lookup("controller:topic")?.model?.category
          : null,
    };
  }

  function focusedWorkspace() {
    const currentWorkspace = currentWorkspaceCategory(services());

    if (currentWorkspace) {
      return currentWorkspace;
    }

    if (
      !document
        .querySelector(".sidebar-sections")
        ?.classList.contains("workspace-team-sidebar--focused")
    ) {
      return null;
    }

    const workspaceId = focusedWorkspaceId();

    return (
      memberWorkspaceCategories(services()).find(
        (workspace) => Number(workspace.id) === workspaceId
      ) ?? null
    );
  }

  function updateLogoLink() {
    const logoLink = document.querySelector(".d-header .title a");

    if (!logoLink) {
      return;
    }

    const workspace = focusedWorkspace();
    logoLink.href = workspace ? workspaceOverviewPath(workspace) : "/";
  }

  document.addEventListener(
    "click",
    (event) => {
      const logoLink = event.target.closest?.(".d-header .title a");

      if (!logoLink) {
        return;
      }

      const workspace = focusedWorkspace();

      if (!workspace) {
        return;
      }

      event.preventDefault();
      DiscourseURL.routeTo(workspaceOverviewPath(workspace));
    },
    true
  );

  api.onPageChange(updateLogoLink);
});
