import Component from "@glimmer/component";
import { service } from "@ember/service";
import BlockOutlet from "discourse/blocks/block-outlet";
import { sidebarWorkspaceCategory } from "../../lib/workspace-team-sidebar-state";

function lookupServices(owner) {
  return {
    chat: owner.lookup("service:chat"),
    chatChannelsManager: owner.lookup("service:chat-channels-manager"),
    currentUser: owner.lookup("service:current-user"),
    router: owner.lookup("service:router"),
    site: owner.lookup("service:site"),
    siteSettings: owner.lookup("service:site-settings"),
    topicCategory: null,
  };
}

export default class WorkspaceChatChannelPanel extends Component {
  static shouldRender(_outletArgs, _context, owner) {
    const services = lookupServices(owner);

    if (
      !services.site?.mobileView ||
      !services.siteSettings?.discourse_workspace_groups_enabled
    ) {
      return false;
    }

    return !!sidebarWorkspaceCategory(services);
  }

  @service router;

  get routeKey() {
    return this.router.currentURL;
  }

  <template>
    <div
      class="workspace-groups-chat-channel-panel"
      data-workspace-groups-chat-channel-panel={{this.routeKey}}
    >
      <BlockOutlet @name="sidebar-blocks" />
    </div>
  </template>
}
