import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import WorkspaceOverviewChannelCard from "discourse/plugins/discourse-workspace-groups/discourse/components/workspace-overview-channel-card";

module(
  "Discourse Workspace Groups | Component | workspace-overview-channel-card",
  function (hooks) {
    setupRenderingTest(hooks);

    test("renders membership and settings actions in the same action row", async function (assert) {
      this.channel = {
        name: "Lab Notes",
        description: "Bench logs and prototype notes.",
        visibility: "public",
        member_count: 4,
        members_url: "/g/lab-notes",
        topics_url: "/c/quantum-tinkerer/lab-notes/29",
        can_open_topics: true,
        can_view_members: true,
        can_join: false,
        can_leave: true,
        can_archive: true,
        can_unarchive: false,
        archived: false,
        is_pending: false,
      };

      this.noop = () => {};

      await render(
        <template>
          <WorkspaceOverviewChannelCard
            @channel={{this.channel}}
            @onJoin={{this.noop}}
            @onLeave={{this.noop}}
            @onOpenSettings={{this.noop}}
          />
        </template>
      );

      assert
        .dom(".workspace-groups-overview__membership-link")
        .hasAttribute("href", "/g/lab-notes");
      assert.dom(".workspace-groups-overview__card-actions").exists();
      assert.dom(".workspace-groups-overview__card-actions .btn").exists({
        count: 2,
      });
      assert
        .dom(".workspace-groups-overview__membership-button--icon")
        .hasAttribute("title", "Leave");
      assert
        .dom(".workspace-groups-overview__membership-button--icon .d-icon-right-from-bracket")
        .exists();
      assert
        .dom(".workspace-groups-overview__card-actions .d-icon-wrench")
        .exists();
      assert
        .dom(".workspace-groups-overview__card-actions .btn:last-child")
        .hasAttribute("title", "Channel settings");
    });

    test("renders the visibility icon before the channel name and moves the label into a tooltip", async function (assert) {
      this.channel = {
        name: "Secure Lab",
        description: "Restricted channel.",
        visibility: "private",
        member_count: 4,
        members_url: "/g/secure-lab",
        topics_url: "/c/quantum-tinkerer/secure-lab/29",
        can_open_topics: true,
        can_view_members: true,
        can_join: false,
        can_leave: false,
        can_archive: false,
        can_unarchive: false,
        archived: false,
        is_pending: false,
      };

      this.noop = () => {};

      await render(
        <template>
          <WorkspaceOverviewChannelCard
            @channel={{this.channel}}
            @onJoin={{this.noop}}
            @onLeave={{this.noop}}
            @onOpenSettings={{this.noop}}
          />
        </template>
      );

      assert.dom(".workspace-groups-overview__heading h3").hasText("Secure Lab");
      assert
        .dom(".workspace-groups-overview__visibility--title")
        .hasAttribute("title", "Private");
      assert
        .dom(".workspace-groups-overview__visibility--title .d-icon-lock")
        .exists();
      assert.dom(".workspace-groups-overview__badges").hasNoText();
    });

    test("renders cooked channel descriptions with links", async function (assert) {
      this.channel = {
        name: "Docs",
        description: "Read the docs.",
        description_cooked:
          '<p>Read <a href="https://example.com/docs" rel="noopener nofollow ugc">the docs</a>.</p>',
        visibility: "public",
        member_count: 4,
        members_url: "/g/docs",
        topics_url: "/c/quantum-tinkerer/docs/29",
        can_open_topics: true,
        can_view_members: true,
        can_join: false,
        can_leave: false,
        can_archive: false,
        can_unarchive: false,
        archived: false,
        is_pending: false,
      };

      this.noop = () => {};

      await render(
        <template>
          <WorkspaceOverviewChannelCard
            @channel={{this.channel}}
            @onJoin={{this.noop}}
            @onLeave={{this.noop}}
            @onOpenSettings={{this.noop}}
          />
        </template>
      );

      assert
        .dom(".workspace-groups-overview__channel-description a")
        .hasAttribute("href", "https://example.com/docs");
      assert.dom(".workspace-groups-overview__channel-description").includesText("Read the docs.");
    });

    test("flattens wrapped pipe-separated link descriptions without dropping links", async function (assert) {
      this.channel = {
        name: "Adaptive",
        description_cooked:
          '<p><a href="https://example.com/repo">repo</a> | <a href="https://example.com/docs">docs</a> |<br>\n<a href="https://example.com/paper">paper</a> | <a href="https://example.com/manuscript">manuscript</a></p>',
        visibility: "public",
        member_count: 4,
        members_url: "/g/adaptive",
        topics_url: "/c/quantum-tinkerer/adaptive/29",
        can_open_topics: true,
        can_view_members: true,
        can_join: false,
        can_leave: false,
        can_archive: false,
        can_unarchive: false,
        archived: false,
        is_pending: false,
      };

      this.noop = () => {};

      await render(
        <template>
          <WorkspaceOverviewChannelCard
            @channel={{this.channel}}
            @onJoin={{this.noop}}
            @onLeave={{this.noop}}
            @onOpenSettings={{this.noop}}
          />
        </template>
      );

      assert
        .dom(".workspace-groups-overview__channel-description")
        .hasText("repo | docs | paper | manuscript");
      assert
        .dom(".workspace-groups-overview__channel-description")
        .doesNotContainText("\n");
      assert.dom(".workspace-groups-overview__channel-description br").doesNotExist();
      assert
        .dom(".workspace-groups-overview__channel-description a")
        .exists({ count: 4 });
    });
  }
);
