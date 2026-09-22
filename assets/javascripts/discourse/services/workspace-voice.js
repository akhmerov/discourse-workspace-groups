import { tracked } from "@glimmer/tracking";
import Service, { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { bind } from "discourse/lib/decorators";

export default class WorkspaceVoiceService extends Service {
  @service currentUser;
  @service messageBus;
  @service siteSettings;
  @service voiceRooms;
  @service voiceWebrtc;

  @tracked channels = [];
  pendingRingRoomId = null;
  refreshTimer = null;

  constructor() {
    super(...arguments);
    if (this.currentUser) {
      this.refreshTimer = setInterval(() => {
        this.refresh().catch(() => {});
      }, 15000);
      this.messageBus.subscribe(
        `/workspace-voice/revoked/${this.currentUser.id}`,
        this.revoked
      );
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    clearInterval(this.refreshTimer);
    if (this.currentUser) {
      this.messageBus.unsubscribe(
        `/workspace-voice/revoked/${this.currentUser.id}`,
        this.revoked
      );
    }
  }

  async refresh() {
    if (
      !this.currentUser ||
      !this.siteSettings.voice_enabled ||
      !this.siteSettings.discourse_workspace_groups_enabled
    ) {
      this.channels = [];
      return;
    }
    const result = await ajax("/workspace-groups/voice/rooms.json");
    await this.voiceRooms.ready;
    result.channels.forEach((channel) => {
      if (channel.room) {
        this.voiceRooms.upsertRoom(channel.room);
      }
    });
    this.channels = result.channels;
  }

  async prepare(sourceType, sourceId) {
    const result = await ajax("/workspace-groups/voice/prepare", {
      type: "POST",
      data: { source_type: sourceType, source_id: sourceId },
    });
    await this.voiceRooms.ready;
    this.voiceRooms.upsertRoom(result.room);
    if (
      sourceType === "dm" &&
      !result.room.active_participants?.length &&
      this.currentUser.workspace_voice_can_start_dm
    ) {
      this.pendingRingRoomId = result.room.id;
    }
    return result.room;
  }

  @bind
  async revoked(message) {
    const room = this.voiceRooms.roomById(message.room_id);
    if (room) {
      this.voiceWebrtc.leave(room, { skipServer: true });
      this.voiceRooms.handleDirectoryEvent({ type: "destroyed", room });
    }
    await this.refresh();
  }
}
