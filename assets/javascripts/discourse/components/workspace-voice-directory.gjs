import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class WorkspaceVoiceDirectory extends Component {
  @service workspaceVoice;
  @service voiceRooms;
  @service voiceWebrtc;

  @tracked retrying = false;

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

  @action
  async retry() {
    this.retrying = true;
    try {
      await this.workspaceVoice.refresh();
    } catch {
      // The service records the failure; the error state stays visible.
    } finally {
      this.retrying = false;
    }
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
      {{#if this.workspaceVoice.loadFailed}}
        <div class="workspace-voice-directory__error">
          <p>{{i18n "discourse_workspace_groups.voice.load_failed"}}</p>
          <DButton
            @action={{this.retry}}
            @label="discourse_workspace_groups.retry"
            @icon="arrows-rotate"
            @disabled={{this.retrying}}
            class="btn-default workspace-voice-directory__retry"
          />
        </div>
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
        {{#unless this.workspaceVoice.loadFailed}}
          <p>{{i18n "discourse_workspace_groups.voice.empty"}}</p>
        {{/unless}}
      {{/each}}
    </section>
  </template>
}
