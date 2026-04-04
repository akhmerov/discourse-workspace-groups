import Category from "discourse/models/category";
import { canDisplayCategory } from "discourse/lib/sidebar/helpers";

export const LAST_WORKSPACE_KEY = "workspace-groups:last-workspace-id";

export function workspaceScopedCategory(category) {
  if (!category) {
    return null;
  }

  if (
    category.workspace_enabled ||
    category.workspace_kind === "workspace" ||
    category.workspace_kind === "channel"
  ) {
    return category;
  }

  return null;
}

function visibleChildren(category, siteSettings, site) {
  if (!category || !site?.categoriesList?.length) {
    return [];
  }

  return site.categoriesList.filter(
    (candidate) =>
      candidate.parent_category_id === category.id &&
      canDisplayCategory(candidate.id, siteSettings)
  );
}

function pushUniqueCategory(categories, category) {
  if (!category) {
    return categories;
  }

  if (categories.some((candidate) => candidate.id === category.id)) {
    return categories;
  }

  return [...categories, category];
}

function scopedCategoriesFor(category, services) {
  if (!category) {
    return null;
  }

  const directChildren = visibleChildren(
    category,
    services.siteSettings,
    services.site
  );

  if (directChildren.length > 0) {
    return [category, ...directChildren];
  }

  if (category.parent_category_id) {
    const parentCategory = Category.findById(category.parent_category_id);
    const siblingCategories = visibleChildren(
      parentCategory,
      services.siteSettings,
      services.site
    );

    if (siblingCategories.length > 0) {
      return [parentCategory, ...siblingCategories];
    }
  }

  return [];
}

function routeCategoryFor(services) {
  const routeCategory = services.router?.currentRoute?.attributes?.category;
  if (routeCategory) {
    return workspaceScopedCategory(routeCategory);
  }

  return null;
}

function topicCategoryFor(services) {
  if (!services.router?.currentRouteName?.startsWith("topic.")) {
    return null;
  }

  return workspaceScopedCategory(services.topicCategory);
}

function chatCategoryFor(services) {
  const activeChannel = services.chat?.activeChannel;

  if (!activeChannel?.isCategoryChannel || !activeChannel.chatableId) {
    return null;
  }

  return workspaceScopedCategory(Category.findById(activeChannel.chatableId));
}

export function currentScopedCategory(services) {
  return (
    routeCategoryFor(services) ||
    topicCategoryFor(services) ||
    chatCategoryFor(services)
  );
}

export function currentWorkspaceCategory(services) {
  return scopedCategoriesFor(currentScopedCategory(services), services)?.[0] ?? null;
}

export function currentScopedMode(services) {
  if (
    services.router?.currentRouteName?.startsWith("chat.") &&
    services.chat?.activeChannel?.isCategoryChannel
  ) {
    return "chat";
  }

  return currentScopedCategory(services) ? "category" : null;
}

export function sidebarScopedCategories(services) {
  const currentCategories = scopedCategoriesFor(currentScopedCategory(services), services);

  if (currentCategories) {
    return currentCategories;
  }

  const fallbackWorkspace = rememberedOrDefaultWorkspaceCategory(services);
  return scopedCategoriesFor(fallbackWorkspace, services);
}

export function userSelectedScopedCategories(currentUser, scopedCategories) {
  const selectedIds = currentUser?.sidebarCategoryIds;

  if (!selectedIds?.length || !scopedCategories.length) {
    return null;
  }

  const [topLevelCategory, ...subcategories] = scopedCategories;
  const selectedScopedCategories = subcategories.filter((category) =>
    selectedIds.includes(category.id)
  );

  if (
    selectedScopedCategories.length > 0 &&
    selectedScopedCategories.length < subcategories.length
  ) {
    return [topLevelCategory, ...selectedScopedCategories];
  }

  return null;
}

export function pairedCategoryChannelFor(category, chatChannelsManager) {
  return chatChannelsManager?.channels?.find(
    (channel) =>
      channel.isCategoryChannel &&
      channel.chatableId === category.id &&
      channel.currentUserMembership?.following
  );
}

export function sidebarChannelCategories(services) {
  const scopedCategories = sidebarScopedCategories(services);

  if (!scopedCategories?.length) {
    return null;
  }

  let visibleCategories =
    userSelectedScopedCategories(services.currentUser, scopedCategories) ??
    scopedCategories;
  const currentCategory = currentScopedCategory(services);
  const currentWorkspace = scopedCategories[0];

  if (
    currentCategory?.workspace_kind === "channel" &&
    currentCategory.parent_category_id === currentWorkspace?.id
  ) {
    visibleCategories = pushUniqueCategory(visibleCategories, currentCategory);
  }

  return visibleCategories
    .slice(1)
    .filter((category) =>
      pairedCategoryChannelFor(category, services.chatChannelsManager) ||
      category.id === currentCategory?.id
    );
}

export function sidebarWorkspaceCategory(services) {
  return sidebarScopedCategories(services)?.[0] ?? null;
}

export function workspaceOverviewPath(category) {
  if (!category) {
    return null;
  }

  return `${category.path}/overview`;
}

export function visibleWorkspaceCategories(services) {
  if (!services.site?.categoriesList?.length) {
    return [];
  }

  return services.site.categoriesList.filter(
    (category) =>
      !category.parent_category_id &&
      category.workspace_kind === "workspace" &&
      canDisplayCategory(category.id, services.siteSettings)
  );
}

export function memberWorkspaceCategories(services) {
  const workspaceGroupIds = new Set(
    (services.currentUser?.groups || []).map((group) => Number(group.id))
  );

  return visibleWorkspaceCategories(services).filter((category) =>
    workspaceGroupIds.has(Number(category.workspace_group_id))
  );
}

export function rememberedWorkspaceCategory(services) {
  let rememberedId;

  try {
    rememberedId = Number(localStorage.getItem(LAST_WORKSPACE_KEY));
  } catch {
    return null;
  }

  if (!rememberedId) {
    return null;
  }

  return (
    visibleWorkspaceCategories(services).find(
      (category) => Number(category.id) === rememberedId
    ) ?? null
  );
}

export function rememberedOrDefaultWorkspaceCategory(services) {
  return (
    rememberedWorkspaceCategory(services) ||
    memberWorkspaceCategories(services)[0] ||
    null
  );
}
