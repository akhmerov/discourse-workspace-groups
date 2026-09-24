import Component from "@glimmer/component";
import Category from "discourse/models/category";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import CoreChannelChatable from "discourse/plugins/chat/discourse/components/chat/message-creator/channel" with {
  discourseImport: "optional",
};

// Names the team of each team channel in chat's quick palette, where channels from
// different teams can share a name.
export default class WorkspaceChannelChatable extends Component {
  get chatable() {
    return this.args.item?.model?.chatable;
  }

  get isTeamChannel() {
    return this.chatable?.workspace_kind === "channel";
  }

  get teamName() {
    if (!this.isTeamChannel) {
      return null;
    }

    const teamId =
      this.chatable.workspace_parent_category_id ??
      this.chatable.parent_category_id;

    return teamId ? Category.findById(teamId)?.name : null;
  }

  // Every team channel is a restricted category; the lock only means something for
  // private channels.
  get isPublicTeamChannel() {
    return (
      this.isTeamChannel && this.chatable.workspace_visibility === "public"
    );
  }

  <template>
    <div
      class={{dConcatClass
        "workspace-channel-chatable"
        (if this.isPublicTeamChannel "workspace-channel-chatable--public")
      }}
    >
      <CoreChannelChatable @item={{@item}} />

      {{#if this.teamName}}
        <span class="workspace-channel-chatable__team">{{this.teamName}}</span>
      {{/if}}
    </div>
  </template>
}
