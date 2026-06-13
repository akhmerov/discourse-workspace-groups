import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import BlockOutlet from "discourse/blocks/block-outlet";
import {
  focusedWorkspaceCategory,
  memberWorkspaceCategories,
  WORKSPACE_FOCUS_CHANGED_EVENT,
} from "../../lib/workspace-team-sidebar-state";

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

    return memberWorkspaceCategories(services).length > 0;
  }

  @service router;
  @service chat;
  @service("chat-channels-manager") chatChannelsManager;
  @service currentUser;
  @service site;
  @service("site-settings") siteSettings;

  @tracked focusVersion = 0;

  constructor() {
    super(...arguments);

    this.focusChangedCallback = () => this.focusVersion++;
    window.addEventListener(
      WORKSPACE_FOCUS_CHANGED_EVENT,
      this.focusChangedCallback
    );
  }

  willDestroy() {
    super.willDestroy(...arguments);

    window.removeEventListener(
      WORKSPACE_FOCUS_CHANGED_EVENT,
      this.focusChangedCallback
    );
  }

  get services() {
    return {
      chat: this.chat,
      chatChannelsManager: this.chatChannelsManager,
      currentUser: this.currentUser,
      router: this.router,
      site: this.site,
      siteSettings: this.siteSettings,
      topicCategory: null,
    };
  }

  get focusedWorkspace() {
    this.focusVersion;
    return focusedWorkspaceCategory(this.services);
  }

  get routeKey() {
    return this.router.currentURL;
  }

  <template>
    {{#if this.focusedWorkspace}}
      <div
        class="workspace-groups-chat-channel-panel"
        data-workspace-groups-chat-channel-panel={{this.routeKey}}
      >
        <BlockOutlet @name="sidebar-blocks" />
      </div>
    {{/if}}
  </template>
}
