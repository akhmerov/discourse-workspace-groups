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

export function workspaceChannelMode(category) {
  return category?.workspace_channel_mode || "both";
}

export function workspaceCategoryModeEnabled(category) {
  return workspaceChannelMode(category) !== "chat_only";
}

export function workspaceChatModeEnabled(category) {
  return workspaceChannelMode(category) !== "category_only";
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

export function workspaceSidebarOrders(currentUser) {
  return (
    currentUser?.workspaceSidebarOrders ??
    currentUser?.workspace_sidebar_orders ??
    {}
  );
}

export function workspaceSidebarChannelOrder(currentUser, workspaceId) {
  if (!workspaceId) {
    return [];
  }

  return workspaceSidebarOrders(currentUser)?.[String(workspaceId)] ?? [];
}

function sortCategoriesByExplicitOrder(categories, orderedIds) {
  if (!orderedIds?.length) {
    return categories;
  }

  const orderIndex = new Map(
    orderedIds.map((categoryId, index) => [categoryId, index])
  );

  return [...categories].sort((left, right) => {
    const leftIndex = orderIndex.get(left.id);
    const rightIndex = orderIndex.get(right.id);

    if (leftIndex !== undefined && rightIndex !== undefined) {
      return leftIndex - rightIndex;
    }

    if (leftIndex !== undefined) {
      return -1;
    }

    if (rightIndex !== undefined) {
      return 1;
    }

    return 0;
  });
}

export function pairedCategoryChannelFor(category, chatChannelsManager) {
  if (!workspaceChatModeEnabled(category)) {
    return null;
  }

  return chatChannelsManager?.channels?.find(
    (channel) =>
      channel.isCategoryChannel &&
      channel.chatableId === category.id &&
      channel.currentUserMembership?.following
  );
}

export function sidebarChannelCategories(services, orderedIdsOverride = null) {
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

  const visibleChannelEntries = visibleCategories
    .slice(1)
    .filter((category) => {
      if (category.id === currentCategory?.id) {
        return true;
      }

      if (!workspaceChatModeEnabled(category)) {
        return workspaceCategoryModeEnabled(category);
      }

      return !!pairedCategoryChannelFor(category, services.chatChannelsManager);
    })
    .map((category, index) => ({
      category,
      index,
      muted: !!pairedCategoryChannelFor(category, services.chatChannelsManager)
        ?.currentUserMembership?.muted,
    }));

  const explicitOrder =
    orderedIdsOverride ??
    workspaceSidebarChannelOrder(services.currentUser, currentWorkspace?.id);

  if (explicitOrder.length > 0) {
    return sortCategoriesByExplicitOrder(
      visibleChannelEntries.map(({ category }) => category),
      explicitOrder
    );
  }

  return visibleChannelEntries
    .sort((left, right) => {
      if (left.muted === right.muted) {
        return left.index - right.index;
      }

      return left.muted ? 1 : -1;
    })
    .map(({ category }) => category);
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
    memberWorkspaceCategories(services).find(
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
