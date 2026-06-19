import { module, test } from "qunit";
import {
  isEventCategory,
  setEventCategory,
} from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-event-categories";

module("Discourse Workspace Groups | Unit | workspace-event-categories", function () {
  test("reads event categories from the Calendar site setting", function (assert) {
    const siteSettings = { events_calendar_categories: "12|29" };

    assert.true(isEventCategory(siteSettings, { id: 29 }));
    assert.false(isEventCategory(siteSettings, { id: 30 }));
  });

  test("updates event categories in the Calendar site setting", function (assert) {
    const siteSettings = { events_calendar_categories: "12|29" };

    setEventCategory(siteSettings, 30, true);
    assert.strictEqual(siteSettings.events_calendar_categories, "12|29|30");

    setEventCategory(siteSettings, 29, false);
    assert.strictEqual(siteSettings.events_calendar_categories, "12|30");
  });
});
