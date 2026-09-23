import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class WorkspaceVoiceIndexRoute extends DiscourseRoute {
  @service workspaceVoice;

  async model() {
    // The directory renders its own error state when the refresh fails.
    await this.workspaceVoice.refresh().catch(() => {});
    return this.workspaceVoice.channels;
  }

  titleToken() {
    return i18n("discourse_workspace_groups.voice.title");
  }
}
