import { module, test } from "qunit";
import sinon from "sinon";
import Category from "discourse/models/category";
import pretender from "discourse/tests/helpers/create-pretender";
import { setupTest } from "discourse/tests/helpers/index";

module("Discourse Workspace Groups | Route | workspace-overview", function (hooks) {
  setupTest(hooks);

  hooks.afterEach(function () {
    sinon.restore();
  });

  test("falls back to async category lookup when the category is not cached", async function (assert) {
    pretender.get("/workspace-groups/workspaces/28.json", () => [
      200,
      { "Content-Type": "application/json" },
      JSON.stringify({
        workspace: { id: 28, name: "Quantum Tinkerer" },
        channels: [],
      }),
    ]);

    const workspace = {
      id: 28,
      url: "/c/quantum-tinkerer/28",
      workspace_kind: "workspace",
    };

    sinon.stub(Category, "findBySlugPathWithID").returns(null);
    const asyncLookup = sinon
      .stub(Category, "asyncFindBySlugPathWithID")
      .resolves(workspace);

    const route = this.owner.lookup("route:discovery.workspaceOverview");
    const redirect = sinon.stub(route.router, "replaceWith");

    const model = await route.model({
      category_slug_path_with_id: "quantum-tinkerer/28",
    });

    assert.true(asyncLookup.calledOnceWith("quantum-tinkerer/28"));
    assert.strictEqual(model.category, workspace);
    assert.strictEqual(model.channels.length, 0);
    assert.false(redirect.called);
  });

  test("redirects to 404 when async lookup also fails", async function (assert) {
    sinon.stub(Category, "findBySlugPathWithID").returns(null);
    sinon.stub(Category, "asyncFindBySlugPathWithID").rejects();

    const route = this.owner.lookup("route:discovery.workspaceOverview");
    const redirect = sinon.stub(route.router, "replaceWith");

    const model = await route.model({
      category_slug_path_with_id: "quantum-tinkerer/28",
    });

    assert.strictEqual(model, undefined);
    assert.true(redirect.calledOnceWith("/404"));
  });
});
