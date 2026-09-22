import { popupAjaxError } from "discourse/lib/ajax-error";
import { apiInitializer } from "discourse/lib/api";
import WorkspaceVoiceHeader from "../components/workspace-voice-header";

export default apiInitializer((api) => {
  const settings = api.container.lookup("service:site-settings");
  if (!settings.discourse_workspace_groups_enabled || !settings.voice_enabled) {
    return;
  }
  api.headerIcons.add("workspace-voice", WorkspaceVoiceHeader, {
    after: "chat",
    before: "user-menu",
  });
  const voice = api.container.lookup("service:workspace-voice");
  voice.refresh().catch(popupAjaxError);
});
