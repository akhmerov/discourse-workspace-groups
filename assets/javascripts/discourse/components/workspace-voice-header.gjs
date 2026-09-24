import Component from "@glimmer/component";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import optionalService from "discourse/lib/optional-service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class WorkspaceVoiceHeader extends Component {
  @service siteSettings;
  @service currentUser;
  @optionalService voiceWebrtc;

  <template>
    {{#if this.currentUser}}
      {{#if this.siteSettings.voice_enabled}}
        <li class="header-dropdown-toggle workspace-voice-header">
          <LinkTo
            aria-label={{i18n "discourse_workspace_groups.voice.title"}}
            class="icon btn-flat"
            title={{i18n "discourse_workspace_groups.voice.title"}}
            @route="workspace-voice.index"
          >
            {{dIcon "microphone"}}
            {{#if this.voiceWebrtc.activeRoomId}}<span
                class="workspace-voice-header__active"
              ></span>{{/if}}
          </LinkTo>
        </li>
      {{/if}}
    {{/if}}
  </template>
}
