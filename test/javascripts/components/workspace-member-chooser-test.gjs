import { click, render, settled, waitUntil } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import WorkspaceMemberChooser from "discourse/plugins/discourse-workspace-groups/discourse/components/workspace-member-chooser";

const searchUrl =
  "/workspace-groups/workspaces/28/channels/29/access/search.json";
const user = (username) => ({
  username,
  avatar_template: "/letter_avatar_proxy/v4/letter/v/123456/{size}.png",
  external: true,
});

module(
  "Discourse Workspace Groups | Component | workspace-member-chooser",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(async function () {
      const context = this;
      this.Chooser = class extends WorkspaceMemberChooser {
        didInsertElement() {
          super.didInsertElement(...arguments);
          context.chooser = this;
        }
      };
      this.options = { memberSearchUrl: searchUrl };
      this.value = [];
      await render(
        <template>
          <this.Chooser @value={{this.value}} @options={{this.options}} />
        </template>
      );
      await click(".user-chooser .select-kit-header");
    });

    test("a late older response cannot replace the newest suggestions", async function (assert) {
      const requests = {};
      pretender.get(
        searchUrl,
        (request) => {
          requests[request.queryParams.term] = request;
          return response({ users: [user(request.queryParams.term)] });
        },
        true
      );

      const older = this.chooser._searchWrapper("vic");
      const newer = this.chooser._searchWrapper("victor");
      await waitUntil(() => requests.vic && requests.victor);
      pretender.resolve(requests.victor);
      await newer;
      pretender.resolve(requests.vic);
      await older;
      await settled();
      assert.deepEqual(
        this.chooser.mainCollection.map((item) => item.username),
        ["victor"]
      );
    });

    test("all in-flight searches follow the latest request even when it changes again", async function (assert) {
      const requests = {};
      pretender.get(
        searchUrl,
        (request) => {
          requests[request.queryParams.term] = request;
          return response({ users: [user(request.queryParams.term)] });
        },
        true
      );

      const first = this.chooser._searchWrapper("vic");
      const second = this.chooser._searchWrapper("victor");
      await waitUntil(() => requests.vic && requests.victor);
      pretender.resolve(requests.vic);
      const third = this.chooser._searchWrapper("victormp");
      await waitUntil(() => requests.victormp);
      pretender.resolve(requests.victor);
      pretender.resolve(requests.victormp);
      await Promise.all([first, second, third]);
      await settled();
      assert.deepEqual(
        this.chooser.mainCollection.map((item) => item.username),
        ["victormp"]
      );
    });

    test("clearing the filter invalidates an in-flight search", async function (assert) {
      let request;
      pretender.get(
        searchUrl,
        (pending) => {
          request = pending;
          return response({ users: [user("victormp")] });
        },
        true
      );
      const pending = this.chooser._searchWrapper("vic");
      await waitUntil(() => request);
      await this.chooser._searchWrapper("");
      pretender.resolve(request);
      await pending;
      await settled();
      assert.deepEqual(this.chooser.mainCollection, []);
      assert.false(this.chooser.selectKit.isLoading);
    });

    test("a failed search shows an inline error, stops loading and can recover", async function (assert) {
      let failed = true;
      pretender.get(searchUrl, () =>
        failed
          ? response(500, { errors: ["Search unavailable"] })
          : response({ users: [user("victormp")] })
      );

      await this.chooser._searchWrapper("vic");
      await settled();
      assert.dom(".select-kit-error").includesText("Search unavailable");
      assert.false(this.chooser.selectKit.isLoading);
      assert.false(this.chooser.selectKit.enterDisabled);

      failed = false;
      await this.chooser._searchWrapper("vic");
      await settled();
      assert.dom(".select-kit-error").doesNotExist();
      assert.deepEqual(
        this.chooser.mainCollection.map((item) => item.username),
        ["victormp"]
      );
    });
  }
);
