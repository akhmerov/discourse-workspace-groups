import { cancel } from "@ember/runloop";
import discourseLater from "discourse/lib/later";

export const WORKSPACE_LOAD_MAX_RETRIES = 3;
export const WORKSPACE_LOAD_RETRY_BASE_DELAY_MS = 2000;

// Records failed per-workspace loads and retries each one with a bounded
// exponential backoff. Once the retries are exhausted the load stays blocked
// until `clear` is called, for example from an explicit Retry action.
export default class WorkspaceLoadRetries {
  failures = new Map();

  constructor({
    maxRetries = WORKSPACE_LOAD_MAX_RETRIES,
    baseDelayMs = WORKSPACE_LOAD_RETRY_BASE_DELAY_MS,
  } = {}) {
    this.maxRetries = maxRetries;
    this.baseDelayMs = baseDelayMs;
  }

  blocked(workspaceId) {
    const failure = this.failures.get(workspaceId);
    return Boolean(failure && (failure.timer || this.exhausted(workspaceId)));
  }

  exhausted(workspaceId) {
    return (this.failures.get(workspaceId)?.attempts ?? 0) > this.maxRetries;
  }

  recordFailure(workspaceId, retry) {
    const failure = this.failures.get(workspaceId) ?? {
      attempts: 0,
      timer: null,
    };

    failure.attempts++;
    this.failures.set(workspaceId, failure);

    if (failure.attempts <= this.maxRetries) {
      failure.timer = discourseLater(() => {
        failure.timer = null;
        retry();
      }, this.baseDelayMs * 2 ** (failure.attempts - 1));
    }
  }

  clear(workspaceId) {
    const failure = this.failures.get(workspaceId);

    if (failure?.timer) {
      cancel(failure.timer);
    }

    this.failures.delete(workspaceId);
  }

  clearAll() {
    [...this.failures.keys()].forEach((workspaceId) => this.clear(workspaceId));
  }
}
