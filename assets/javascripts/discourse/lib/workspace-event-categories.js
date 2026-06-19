function normalizeCategoryId(categoryId) {
  return categoryId?.toString();
}

function eventCategoryIds(siteSettings) {
  return (siteSettings.events_calendar_categories || "")
    .split("|")
    .filter(Boolean);
}

function writeEventCategoryIds(siteSettings, categoryIds) {
  const value = [...new Set(categoryIds)].join("|");

  if (typeof siteSettings.set === "function") {
    siteSettings.set("events_calendar_categories", value);
  } else {
    siteSettings.events_calendar_categories = value;
  }
}

export function isEventCategory(siteSettings, category) {
  const categoryId = normalizeCategoryId(category?.id);
  return Boolean(categoryId && eventCategoryIds(siteSettings).includes(categoryId));
}

export function setEventCategory(siteSettings, categoryId, enabled) {
  const id = normalizeCategoryId(categoryId);
  if (!id) {
    return;
  }

  const ids = eventCategoryIds(siteSettings).filter((existingId) => existingId !== id);

  if (enabled) {
    ids.push(id);
  }

  writeEventCategoryIds(siteSettings, ids);
}
