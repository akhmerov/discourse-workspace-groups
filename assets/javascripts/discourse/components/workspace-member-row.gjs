import { classNames } from "@ember-decorators/component";
import formatUsername from "discourse/helpers/format-username";
import SelectKitRow from "discourse/select-kit/components/select-kit/select-kit-row";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";

@classNames("user-row")
export default class WorkspaceMemberRow extends SelectKitRow {
  <template>
    {{dAvatar this.item imageSize="tiny"}}
    <span class="username">{{formatUsername this.item.username}}</span>
    {{#if this.item.name}}
      <span class="name">{{this.item.name}}</span>
    {{/if}}
    {{#if this.item.external}}
      <span class="workspace-groups-member-external">
        {{i18n "discourse_workspace_groups.channel_member_external"}}
      </span>
    {{/if}}
  </template>
}
