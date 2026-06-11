import { apiInitializer } from "discourse/lib/api";
import {
  currentWorkspaceCategory,
  LAST_WORKSPACE_KEY,
} from "../lib/workspace-team-sidebar-state";

const LAST_CATEGORY_KEY = "workspace-groups:last-category-path";
const LEGACY_LAST_CATEGORY_KEY = "research-groups:last-category-path";
const REDIRECT_GUARD_KEY = "workspace-groups:last-category-redirected";
const LEGACY_REDIRECT_GUARD_KEY = "research-groups:last-category-redirected";

function sameOriginUrl(path) {
  if (!path) {
    return null;
  }

  try {
    const url = new URL(path, window.location.origin);

    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }

    if (url.origin !== window.location.origin) {
      return null;
    }

    return url;
  } catch {
    return null;
  }
}

function pathFromSameOriginUrl(url) {
  const normalizedPath = `${url.pathname}${url.search}`;

  return normalizedPath.startsWith("/") ? normalizedPath : null;
}

function normalizePath(path) {
  const url = sameOriginUrl(path);

  return url ? pathFromSameOriginUrl(url) : null;
}

export function normalizeSavedCategoryPath(path) {
  const url = sameOriginUrl(path);

  if (!url) {
    return null;
  }

  if (url.pathname.startsWith("/c/") && url.pathname.endsWith("/overview")) {
    url.pathname = url.pathname.replace(/\/overview$/, "");
  }

  return pathFromSameOriginUrl(url);
}

export function rememberedPathForPage(url, currentCategory) {
  return normalizePath(currentCategory?.path || url);
}

function shouldRedirectToLastCategory(currentLocation = window.location) {
  return (
    currentLocation.pathname === "/" &&
    !currentLocation.search &&
    !currentLocation.hash
  );
}

function savedLastCategoryPath() {
  return normalizeSavedCategoryPath(
    localStorage.getItem(LAST_CATEGORY_KEY) ||
      localStorage.getItem(LEGACY_LAST_CATEGORY_KEY)
  );
}

function redirectGuardSet() {
  return (
    sessionStorage.getItem(REDIRECT_GUARD_KEY) === "1" ||
    sessionStorage.getItem(LEGACY_REDIRECT_GUARD_KEY) === "1"
  );
}

function setRedirectGuard() {
  sessionStorage.setItem(REDIRECT_GUARD_KEY, "1");
  sessionStorage.removeItem(LEGACY_REDIRECT_GUARD_KEY);
}

export function redirectToSavedPath(router, currentLocation = window.location) {
  if (!shouldRedirectToLastCategory(currentLocation)) {
    sessionStorage.removeItem(REDIRECT_GUARD_KEY);
    sessionStorage.removeItem(LEGACY_REDIRECT_GUARD_KEY);
    return false;
  }

  if (redirectGuardSet()) {
    return false;
  }

  const savedPath = savedLastCategoryPath();

  if (!savedPath || savedPath === "/") {
    return false;
  }

  setRedirectGuard();
  router.replaceWith(savedPath);
  return true;
}

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  const router = api.container.lookup("service:router");
  let redirectChecked = false;

  api.onPageChange((url) => {
    if (!redirectChecked) {
      redirectChecked = true;
      if (redirectToSavedPath(router)) {
        return;
      }
    }

    const currentCategory = router.currentRoute?.attributes?.category;
    const currentWorkspace = currentWorkspaceCategory({
      chat: api.container.lookup("service:chat"),
      router,
      site: api.container.lookup("service:site"),
      siteSettings,
      topicCategory:
        router.currentRouteName?.startsWith("topic.")
          ? api.container.lookup("controller:topic")?.model?.category
          : null,
    });

    if (!currentCategory) {
      if (currentWorkspace?.id) {
        localStorage.setItem(LAST_WORKSPACE_KEY, String(currentWorkspace.id));
      }

      return;
    }

    const normalizedUrl = rememberedPathForPage(url, currentCategory);

    if (!normalizedUrl) {
      return;
    }

    localStorage.setItem(LAST_CATEGORY_KEY, normalizedUrl);
    localStorage.removeItem(LEGACY_LAST_CATEGORY_KEY);

    if (currentWorkspace?.id) {
      localStorage.setItem(LAST_WORKSPACE_KEY, String(currentWorkspace.id));
    }
  });
});
