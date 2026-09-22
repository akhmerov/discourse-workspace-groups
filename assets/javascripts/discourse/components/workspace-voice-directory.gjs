import Component from "@glimmer/component";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class WorkspaceVoiceDirectory extends Component {
  @service workspaceVoice;
  @service voiceRooms;
  @service voiceWebrtc;

  get currentRoom() {
    return this.voiceRooms.roomById(this.voiceWebrtc.activeRoomId);
  }

  get workspaces() {
    const groups = new Map();
    this.workspaceVoice.channels.forEach((channel) => {
      const room = this.voiceRooms.rooms.find(
        (candidate) => candidate.id === channel.room?.id
      );
      const participants = room?.active_participants || [];
      if (!groups.has(channel.workspace_id)) {
        groups.set(channel.workspace_id, {
          id: channel.workspace_id,
          name: channel.workspace_name,
          channels: [],
        });
      }
      groups.get(channel.workspace_id).channels.push({
        ...channel,
        participants,
        count: participants.length,
      });
    });
    return [...groups.values()]
      .sort((a, b) => a.name.localeCompare(b.name))
      .map((group) => ({
        ...group,
        channels: group.channels.sort(
          (a, b) => b.count - a.count || a.name.localeCompare(b.name)
        ),
      }));
  }

  <template>
    <section class="workspace-voice-directory">
      <h1>{{dIcon "microphone"}}
        {{i18n "discourse_workspace_groups.voice.title"}}</h1>
      {{#if this.currentRoom}}
        <LinkTo
          class="btn btn-primary"
          @model={{this.currentRoom.slug}}
          @route="voice-room"
        >
          {{i18n "discourse_workspace_groups.voice.return_to_call"}}
        </LinkTo>
      {{/if}}
      {{#each this.workspaces as |workspace|}}
        <section class="workspace-voice-directory__workspace">
          <h2>{{workspace.name}}</h2>
          {{#each workspace.channels as |channel|}}
            <LinkTo
              class="workspace-voice-directory__room"
              @model={{channel.category_id}}
              @route="workspace-voice.channel"
            >
              <span>{{dIcon "microphone"}} {{channel.name}}</span>
              <span class="workspace-voice-directory__participants">
                {{#each channel.participants as |participant|}}{{dAvatar
                    participant
                    imageSize="small"
                  }}{{/each}}
                {{i18n
                  "discourse_workspace_groups.voice.participant_count"
                  count=channel.count
                }}
              </span>
            </LinkTo>
          {{/each}}
        </section>
      {{else}}
        <p>{{i18n "discourse_workspace_groups.voice.empty"}}</p>
      {{/each}}
    </section>
  </template>
}
