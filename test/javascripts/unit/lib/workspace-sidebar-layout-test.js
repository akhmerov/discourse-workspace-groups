import { module, test } from "qunit";
import {
  appendSidebarSection,
  channelIdsForLayout,
  DEFAULT_SIDEBAR_SECTION_ID,
  deleteSidebarSection,
  editableSidebarLayout,
  insertSidebarSection,
  moveCategoryInSidebarLayout,
  moveSidebarSectionInLayout,
  normalizeSidebarLayout,
  OTHER_SECTION_ID,
  renameSidebarSection,
  sidebarLayoutFromState,
  toggleSidebarSectionCollapsed,
  uniqueSidebarSectionId,
} from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-sidebar-layout";
import { contracts as layoutContracts } from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-sidebar-layout-contracts";

module(
  "Discourse Workspace Groups | Lib | workspace-sidebar-layout",
  function () {
    for (const contract of layoutContracts) {
      test(`normalizes ${contract.name}`, function (assert) {
        assert.deepEqual(
          normalizeSidebarLayout(contract.input),
          contract.normalized
        );
      });
    }

    test("builds a legacy layout when no section layout exists", function (assert) {
      assert.deepEqual(sidebarLayoutFromState(null, [42, "43", "bad"]), {
        sections: [
          {
            id: DEFAULT_SIDEBAR_SECTION_ID,
            title: "Channels",
            channel_ids: [42, 43],
            collapsed: false,
          },
        ],
        other_channel_ids: [],
        other_collapsed: false,
      });
    });

    test("repairs editable layouts against visible rows", function (assert) {
      const rows = [
        { category: { id: 42 } },
        { category: { id: 44 } },
        { category: { id: 45 } },
      ];

      assert.deepEqual(
        editableSidebarLayout(
          {
            sections: [
              {
                id: "papers",
                title: "Papers",
                channel_ids: [42, 43],
                collapsed: true,
              },
            ],
            other_channel_ids: [44],
            other_collapsed: true,
          },
          rows
        ),
        {
          sections: [
            {
              id: "papers",
              title: "Papers",
              channel_ids: [42],
              collapsed: true,
            },
          ],
          other_channel_ids: [44, 45],
          other_collapsed: true,
        }
      );
    });

    test("moves channels between sections without changing collapsed state", function (assert) {
      const layout = {
        sections: [
          {
            id: "papers",
            title: "Papers",
            channel_ids: [41, 42],
            collapsed: true,
          },
          {
            id: "students",
            title: "Students",
            channel_ids: [43],
            collapsed: false,
          },
        ],
        other_channel_ids: [44],
        other_collapsed: true,
      };

      const movedToSection = moveCategoryInSidebarLayout(
        layout,
        44,
        "students",
        43,
        "before"
      );

      assert.deepEqual(movedToSection, {
        sections: [
          {
            id: "papers",
            title: "Papers",
            channel_ids: [41, 42],
            collapsed: true,
          },
          {
            id: "students",
            title: "Students",
            channel_ids: [44, 43],
            collapsed: false,
          },
        ],
        other_channel_ids: [],
        other_collapsed: true,
      });

      assert.deepEqual(
        moveCategoryInSidebarLayout(movedToSection, 41, OTHER_SECTION_ID),
        {
          sections: [
            {
              id: "papers",
              title: "Papers",
              channel_ids: [42],
              collapsed: true,
            },
            {
              id: "students",
              title: "Students",
              channel_ids: [44, 43],
              collapsed: false,
            },
          ],
          other_channel_ids: [41],
          other_collapsed: true,
        }
      );
    });

    test("renames, appends, deletes, and toggles sections", function (assert) {
      const layout = appendSidebarSection(
        {
          sections: [
            {
              id: "papers",
              title: "Papers",
              channel_ids: [41],
              collapsed: false,
            },
          ],
          other_channel_ids: [42],
          other_collapsed: true,
        },
        {
          id: uniqueSidebarSectionId({ sections: [{ id: "section-100" }] }, 100),
          title: "Students",
        }
      );

      assert.deepEqual(layout.sections.map((section) => section.id), [
        "papers",
        "section-100-1",
      ]);

      const renamed = renameSidebarSection(layout, "section-100-1", "  Lab  ");
      const toggled = toggleSidebarSectionCollapsed(renamed, "section-100-1");
      const deleted = deleteSidebarSection(toggled, "papers");

      assert.deepEqual(deleted, {
        sections: [
          {
            id: "section-100-1",
            title: "Lab",
            channel_ids: [],
            collapsed: true,
          },
        ],
        other_channel_ids: [42, 41],
        other_collapsed: false,
      });

      assert.deepEqual(channelIdsForLayout(deleted), [42, 41]);
      assert.strictEqual(
        renameSidebarSection(deleted, "section-100-1", " "),
        null
      );
      assert.strictEqual(deleteSidebarSection(deleted, "missing"), null);
    });

    test("inserts and reorders sections", function (assert) {
      const layout = {
        sections: [
          {
            id: "papers",
            title: "Papers",
            channel_ids: [41],
            collapsed: false,
          },
          {
            id: "students",
            title: "Students",
            channel_ids: [42],
            collapsed: true,
          },
        ],
        other_channel_ids: [43],
        other_collapsed: false,
      };

      const inserted = insertSidebarSection(
        layout,
        { id: "announcements", title: "Announcements" },
        0
      );

      assert.deepEqual(
        inserted.sections.map((section) => section.id),
        ["announcements", "papers", "students"]
      );

      assert.deepEqual(
        moveSidebarSectionInLayout(inserted, "students", "announcements"),
        {
          sections: [
            {
              id: "students",
              title: "Students",
              channel_ids: [42],
              collapsed: true,
            },
            {
              id: "announcements",
              title: "Announcements",
              channel_ids: [],
              collapsed: false,
            },
            {
              id: "papers",
              title: "Papers",
              channel_ids: [41],
              collapsed: false,
            },
          ],
          other_channel_ids: [43],
          other_collapsed: false,
        }
      );

      assert.strictEqual(
        moveSidebarSectionInLayout(inserted, "missing", "papers"),
        null
      );
      assert.strictEqual(
        moveSidebarSectionInLayout(inserted, "papers", "missing"),
        null
      );
    });
  }
);
