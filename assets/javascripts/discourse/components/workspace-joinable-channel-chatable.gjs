import Component from "@glimmer/component";
import dIcon from "discourse/ui-kit/helpers/d-icon";

export default class WorkspaceJoinableChannelChatable extends Component {
  get channel() {
    return this.args.item?.channel;
  }

  <template>
    <div class="chat-message-creator__chatable -category-channel workspace-joinable-channel-chatable">
      <span class="workspace-joinable-channel-chatable__icon">
        {{dIcon "right-to-bracket"}}
      </span>

      <span class="workspace-joinable-channel-chatable__content">
        <span class="workspace-joinable-channel-chatable__name">
          {{this.channel.name}}
        </span>

        <span class="workspace-joinable-channel-chatable__workspace">
          {{this.channel.workspace_name}}
        </span>
      </span>
    </div>
  </template>
}
