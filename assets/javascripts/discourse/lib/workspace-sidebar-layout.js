export const DEFAULT_SIDEBAR_SECTION_ID = "channels";
export const DEFAULT_SIDEBAR_SECTION_TITLE = "Channels";
export const OTHER_SECTION_ID = "__other";

const FALSE_VALUES = new Set([
  false,
  0,
  "0",
  "f",
  "F",
  "false",
  "FALSE",
  "off",
  "OFF",
  "",
]);

function layoutOptions(options = {}) {
  return {
    defaultSectionTitle:
      options.defaultSectionTitle || DEFAULT_SIDEBAR_SECTION_TITLE,
  };
}

function objectLike(value) {
  return value && typeof value === "object" && !Array.isArray(value);
}

function arrayWrap(value) {
  if (Array.isArray(value)) {
    return value;
  }

  return value === null || value === undefined ? [] : [value];
}

function presenceString(value, fallback) {
  const string = `${value ?? ""}`.trim();
  return string || fallback;
}

function booleanValue(value) {
  if (value === null || value === undefined) {
    return false;
  }

  return !FALSE_VALUES.has(value);
}

function positiveId(value) {
  const integer = Number.parseInt(value, 10);
  return integer > 0 ? integer : null;
}

function normalizeIdList(value) {
  let values;

  if (Array.isArray(value)) {
    values = value;
  } else if (objectLike(value)) {
    values = Object.values(value);
  } else if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      values = Array.isArray(parsed) ? parsed : value.split(",");
    } catch {
      values = value.split(",");
    }
  } else {
    values = arrayWrap(value);
  }

  const seen = new Set();
  return values
    .map((entry) => positiveId(entry))
    .filter((entry) => {
      if (!entry || seen.has(entry)) {
        return false;
      }

      seen.add(entry);
      return true;
    });
}

function layoutValue(layout, snakeKey, camelKey) {
  return layout?.[snakeKey] ?? layout?.[camelKey];
}

export function normalizeSidebarLayout(layout, options = {}) {
  const { defaultSectionTitle } = layoutOptions(options);
  const rawLayout = objectLike(layout) ? layout : {};
  const seen = new Set();

  const sections = arrayWrap(rawLayout.sections)
    .filter(objectLike)
    .map((section, index) => {
      const channelIds = normalizeIdList(
        layoutValue(section, "channel_ids", "channelIds")
      ).filter((channelId) => {
        if (seen.has(channelId)) {
          return false;
        }

        seen.add(channelId);
        return true;
      });

      return {
        id: presenceString(section.id, `section-${index + 1}`),
        title: presenceString(section.title, defaultSectionTitle),
        channel_ids: channelIds,
        collapsed: booleanValue(section.collapsed),
      };
    });

  const otherChannelIds = normalizeIdList(
    layoutValue(rawLayout, "other_channel_ids", "otherChannelIds")
  ).filter((channelId) => {
    if (seen.has(channelId)) {
      return false;
    }

    seen.add(channelId);
    return true;
  });

  return {
    sections,
    other_channel_ids: otherChannelIds,
    other_collapsed: booleanValue(
      layoutValue(rawLayout, "other_collapsed", "otherCollapsed")
    ),
  };
}

export function emptySidebarLayout() {
  return { sections: [], other_channel_ids: [], other_collapsed: false };
}

export function sidebarLayoutFromState(
  storedLayout,
  legacyChannelIds = [],
  options = {}
) {
  const normalizedLayout = normalizeSidebarLayout(storedLayout, options);

  if (
    normalizedLayout.sections.length > 0 ||
    normalizedLayout.other_channel_ids.length > 0
  ) {
    return normalizedLayout;
  }

  const channelIds = normalizeIdList(legacyChannelIds);

  if (channelIds.length === 0) {
    return emptySidebarLayout();
  }

  return {
    sections: [
      {
        id: DEFAULT_SIDEBAR_SECTION_ID,
        title: layoutOptions(options).defaultSectionTitle,
        channel_ids: channelIds,
        collapsed: false,
      },
    ],
    other_channel_ids: [],
    other_collapsed: false,
  };
}

export function channelIdsForLayout(layout, options = {}) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);

  return [
    ...normalizedLayout.sections.flatMap((section) => section.channel_ids),
    ...normalizedLayout.other_channel_ids,
  ];
}

export function editableSidebarLayout(layout, rows, options = {}) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);
  const rowCategoryIds = rows.map((row) => Number(row.category.id));
  const visibleCategoryIds = new Set(rowCategoryIds);
  const assignedCategoryIds = new Set();

  if (normalizedLayout.sections.length === 0) {
    return {
      sections: [
        {
          id: DEFAULT_SIDEBAR_SECTION_ID,
          title: layoutOptions(options).defaultSectionTitle,
          channel_ids: rowCategoryIds,
          collapsed: false,
        },
      ],
      other_channel_ids: [],
      other_collapsed: false,
    };
  }

  return {
    sections: normalizedLayout.sections.map((section) => ({
      ...section,
      channel_ids: section.channel_ids.filter((categoryId) => {
        const visible = visibleCategoryIds.has(Number(categoryId));

        if (visible) {
          assignedCategoryIds.add(Number(categoryId));
        }

        return visible;
      }),
    })),
    other_channel_ids: [
      ...normalizedLayout.other_channel_ids.filter((categoryId) => {
        const visible = visibleCategoryIds.has(Number(categoryId));

        if (visible) {
          assignedCategoryIds.add(Number(categoryId));
        }

        return visible;
      }),
      ...rowCategoryIds.filter((categoryId) => !assignedCategoryIds.has(categoryId)),
    ],
    other_collapsed: normalizedLayout.other_collapsed,
  };
}

export function channelIdsForSection(layout, sectionId, options = {}) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);

  if (sectionId === OTHER_SECTION_ID) {
    return normalizedLayout.other_channel_ids;
  }

  return (
    normalizedLayout.sections.find((section) => section.id === sectionId)
      ?.channel_ids ?? normalizedLayout.other_channel_ids
  );
}

export function removeCategoryFromSidebarLayout(
  layout,
  categoryId,
  options = {}
) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);
  const normalizedCategoryId = Number(categoryId);

  return {
    ...normalizedLayout,
    sections: normalizedLayout.sections.map((section) => ({
      ...section,
      channel_ids: section.channel_ids.filter(
        (sectionCategoryId) => sectionCategoryId !== normalizedCategoryId
      ),
    })),
    other_channel_ids: normalizedLayout.other_channel_ids.filter(
      (sectionCategoryId) => sectionCategoryId !== normalizedCategoryId
    ),
  };
}

export function moveCategoryInSidebarLayout(
  layout,
  categoryId,
  targetSectionId,
  targetCategoryId = null,
  position = "before",
  options = {}
) {
  const nextLayout = removeCategoryFromSidebarLayout(
    layout,
    categoryId,
    options
  );
  const targetChannelIds =
    targetSectionId === OTHER_SECTION_ID
      ? nextLayout.other_channel_ids
      : nextLayout.sections.find((section) => section.id === targetSectionId)
          ?.channel_ids;

  if (!targetChannelIds) {
    nextLayout.other_channel_ids.push(Number(categoryId));
    return nextLayout;
  }

  const normalizedCategoryId = Number(categoryId);
  const targetIndex = targetCategoryId
    ? targetChannelIds.indexOf(Number(targetCategoryId))
    : -1;
  const insertIndex =
    targetIndex < 0
      ? targetChannelIds.length
      : targetIndex + (position === "after" ? 1 : 0);

  targetChannelIds.splice(insertIndex, 0, normalizedCategoryId);
  return nextLayout;
}

export function uniqueSidebarSectionId(layout, now = Date.now()) {
  const normalizedLayout = normalizeSidebarLayout(layout);
  const existingIds = new Set(
    normalizedLayout.sections.map((section) => section.id)
  );
  let sectionId = `section-${now}`;
  let suffix = 1;

  while (existingIds.has(sectionId)) {
    sectionId = `section-${now}-${suffix++}`;
  }

  return sectionId;
}

export function appendSidebarSection(layout, section, options = {}) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);

  return {
    ...normalizedLayout,
    sections: [
      ...normalizedLayout.sections,
      {
        id: section.id,
        title: section.title,
        channel_ids: [],
        collapsed: false,
      },
    ],
  };
}

export function insertSidebarSection(layout, section, index = 0, options = {}) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);
  const insertIndex = Math.max(
    0,
    Math.min(Number(index) || 0, normalizedLayout.sections.length)
  );
  const nextSections = [...normalizedLayout.sections];

  nextSections.splice(insertIndex, 0, {
    id: section.id,
    title: section.title,
    channel_ids: [],
    collapsed: false,
  });

  return {
    ...normalizedLayout,
    sections: nextSections,
  };
}

export function moveSidebarSectionInLayout(
  layout,
  sectionId,
  targetSectionId,
  position = "before",
  options = {}
) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);

  if (sectionId === targetSectionId) {
    return normalizedLayout;
  }

  const draggedSection = normalizedLayout.sections.find(
    (section) => section.id === sectionId
  );

  if (!draggedSection) {
    return null;
  }

  const nextSections = normalizedLayout.sections.filter(
    (section) => section.id !== sectionId
  );
  const targetIndex = nextSections.findIndex(
    (section) => section.id === targetSectionId
  );

  if (targetIndex < 0) {
    return null;
  }

  nextSections.splice(
    targetIndex + (position === "after" ? 1 : 0),
    0,
    draggedSection
  );

  return {
    ...normalizedLayout,
    sections: nextSections,
  };
}

export function renameSidebarSection(layout, sectionId, title, options = {}) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);
  const trimmedTitle = title.trim();

  if (!trimmedTitle) {
    return null;
  }

  return {
    ...normalizedLayout,
    sections: normalizedLayout.sections.map((section) =>
      section.id === sectionId ? { ...section, title: trimmedTitle } : section
    ),
  };
}

export function deleteSidebarSection(layout, sectionId, options = {}) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);
  const deletedSection = normalizedLayout.sections.find(
    (section) => section.id === sectionId
  );

  if (!deletedSection) {
    return null;
  }

  return {
    ...normalizedLayout,
    sections: normalizedLayout.sections.filter(
      (section) => section.id !== sectionId
    ),
    other_channel_ids: [
      ...normalizedLayout.other_channel_ids,
      ...deletedSection.channel_ids,
    ],
    other_collapsed: deletedSection.channel_ids.length
      ? false
      : normalizedLayout.other_collapsed,
  };
}

export function toggleSidebarSectionCollapsed(
  layout,
  sectionId,
  options = {}
) {
  const normalizedLayout = normalizeSidebarLayout(layout, options);

  return {
    ...normalizedLayout,
    sections: normalizedLayout.sections.map((section) =>
      section.id === sectionId
        ? { ...section, collapsed: !section.collapsed }
        : section
    ),
    other_collapsed:
      sectionId === OTHER_SECTION_ID
        ? !normalizedLayout.other_collapsed
        : normalizedLayout.other_collapsed,
  };
}
