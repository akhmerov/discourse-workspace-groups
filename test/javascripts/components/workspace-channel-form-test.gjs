import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import WorkspaceChannelForm from "discourse/plugins/discourse-workspace-groups/discourse/components/modal/workspace-channel-form";

module(
  "Discourse Workspace Groups | Component | workspace-channel-form",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      this.siteSettings.category_colors = "0088CC|E45735";
    });

    hooks.afterEach(function () {
      sinon.restore();
    });

    test("shows selected swatch changes in the color input", async function (assert) {
      this.set("color", "0088CC");
      this.onColorChange = sinon.spy((color) => this.set("color", color));

      await render(
        <template>
          <WorkspaceChannelForm
            @name="Lab Notes"
            @description=""
            @color={{this.color}}
            @showCategoryStyle={{true}}
            @onColorChange={{this.onColorChange}}
          />
        </template>
      );

      assert
        .dom(".category-color-editor .form-kit__control-color-input-hex")
        .hasValue("0088CC");

      await click(
        '.category-color-editor .form-kit__control-color-swatch[data-color="E45735"]'
      );

      assert.true(this.onColorChange.calledWith("E45735"));
      assert
        .dom(".category-color-editor .form-kit__control-color-input-hex")
        .hasValue("E45735");
    });
  }
);
