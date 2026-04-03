import { apiInitializer } from "discourse/lib/api";

const LAST_CATEGORY_KEY = "workspace-groups:last-category-path";
const LEGACY_LAST_CATEGORY_KEY = "research-groups:last-category-path";
const REDIRECT_GUARD_KEY = "workspace-groups:last-category-redirected";
const LEGACY_REDIRECT_GUARD_KEY = "research-groups:last-category-redirected";

function normalizePath(path) {
  if (!path) {
    return null;
  }

  try {
    const url = new URL(path, window.location.origin);
    return `${url.pathname}${url.search}`;
  } catch {
    return null;
  }
}

function shouldRedirectToLastCategory() {
  return (
    window.location.pathname === "/" &&
    !window.location.search &&
    !window.location.hash
  );
}

function savedLastCategoryPath() {
  return normalizePath(
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

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings?.discourse_workspace_groups_enabled) {
    return;
  }

  const maybeRedirectToLastCategory = () => {
    if (!shouldRedirectToLastCategory()) {
      sessionStorage.removeItem(REDIRECT_GUARD_KEY);
      sessionStorage.removeItem(LEGACY_REDIRECT_GUARD_KEY);
      return;
    }

    if (redirectGuardSet()) {
      return;
    }

    const savedPath = savedLastCategoryPath();

    if (!savedPath || savedPath === "/") {
      return;
    }

    setRedirectGuard();
    window.location.replace(savedPath);
  };

  api.onPageChange((url) => {
    const router = api.container.lookup("service:router");
    const currentCategory = router.currentRoute?.attributes?.category;

    if (!currentCategory) {
      return;
    }

    const normalizedUrl = normalizePath(url);

    if (!normalizedUrl) {
      return;
    }

    localStorage.setItem(LAST_CATEGORY_KEY, normalizedUrl);
    localStorage.removeItem(LEGACY_LAST_CATEGORY_KEY);
  });

  maybeRedirectToLastCategory();
});
