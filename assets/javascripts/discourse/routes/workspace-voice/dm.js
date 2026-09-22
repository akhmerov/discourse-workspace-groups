import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

export default class WorkspaceVoiceDmRoute extends DiscourseRoute {
  @service workspaceVoice;
  @service router;

  model(params) {
    return this.workspaceVoice.prepare("dm", params.channel_id);
  }

  afterModel(room) {
    this.router.replaceWith("voice-room", room.slug);
  }
}
