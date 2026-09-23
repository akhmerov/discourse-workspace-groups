import { settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupTest } from "discourse/tests/helpers/index";
import WorkspaceLoadRetries from "discourse/plugins/discourse-workspace-groups/discourse/lib/workspace-load-retries";

module("Discourse Workspace Groups | Lib | workspace-load-retries", function (hooks) {
  setupTest(hooks);

  test("retries a failed load a bounded number of times", async function (assert) {
    const retries = new WorkspaceLoadRetries({ maxRetries: 2 });
    let attempts = 0;
    const load = () => {
      attempts += 1;
      retries.recordFailure(28, load);
    };

    assert.false(retries.blocked(28));

    load();
    assert.true(retries.blocked(28), "waits for the scheduled retry");
    assert.false(retries.exhausted(28));

    await settled();

    assert.strictEqual(attempts, 3, "initial load plus two retries");
    assert.true(retries.exhausted(28));
    assert.true(retries.blocked(28), "stops retrying once exhausted");
    assert.false(retries.blocked(29), "other workspaces are unaffected");

    retries.clear(28);
    assert.false(retries.blocked(28), "an explicit retry unblocks the load");
    assert.false(retries.exhausted(28));
  });

  test("clearing cancels a pending retry", async function (assert) {
    const retries = new WorkspaceLoadRetries();
    let retried = false;

    retries.recordFailure(28, () => (retried = true));
    retries.clearAll();
    await settled();

    assert.false(retried);
    assert.false(retries.blocked(28));
  });
});
