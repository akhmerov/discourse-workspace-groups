import { tracked } from "@glimmer/tracking";
import Service, { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { bind } from "discourse/lib/decorators";
import optionalService from "discourse/lib/optional-service";

export default class WorkspaceVoiceService extends Service {
  @service currentUser;
  @service messageBus;
  @service siteSettings;
  @optionalService liveRooms;
  @optionalService liveWebrtc;

  @tracked channels = [];
  @tracked loadFailed = false;
  pendingRingRoomId = null;
  refreshTimer = null;
  roomRevision = 0;
  refreshSequence = 0;

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
      this.messageBus.subscribe(
        `/workspace-voice/access/${this.currentUser.id}`,
        this.accessChanged
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
      this.messageBus.unsubscribe(
        `/workspace-voice/access/${this.currentUser.id}`,
        this.accessChanged
      );
    }
  }

  @bind
  accessChanged() {
    // Invalidate any directory request started before this membership change.
    this.roomRevision++;
    this.refresh().catch(() => {});
  }

  async refresh() {
    if (
      !this.currentUser ||
      !this.siteSettings.live_enabled ||
      !this.siteSettings.discourse_workspace_groups_enabled
    ) {
      this.channels = [];
      this.loadFailed = false;
      return;
    }
    const revision = this.roomRevision;
    // Only the most recent request decides whether the directory is stale.
    const sequence = ++this.refreshSequence;
    let result;
    try {
      result = await ajax("/workspace-groups/voice/rooms.json");
    } catch (error) {
      if (sequence === this.refreshSequence) {
        this.loadFailed = true;
      }
      throw error;
    }
    if (sequence === this.refreshSequence) {
      this.loadFailed = false;
    }
    await this.liveRooms.ready;
    if (revision !== this.roomRevision) {
      return;
    }
    // Forget expired or revoked channel rooms so a shared slug is resolved
    // again. A slow directory response must not discard a newer preparation.
    for (const room of this.liveRooms.rooms) {
      const binding = room.workspace_voice;
      if (
        binding?.source_type === "category" &&
        !binding.is_guest &&
        !result.channels.some((channel) => channel.room?.id === room.id)
      ) {
        if (this.liveWebrtc.activeRoomId === room.id) {
          this.liveWebrtc.leave(room, { skipServer: true });
        }
        this.liveRooms.handleDirectoryEvent({ type: "destroyed", room });
      }
    }
    result.channels.forEach((channel) => {
      if (channel.room) {
        this.liveRooms.upsertRoom(channel.room);
      }
    });
    this.channels = result.channels;
  }

  async prepare(sourceType, sourceId) {
    this.roomRevision++;
    const result = await ajax("/workspace-groups/voice/prepare", {
      type: "POST",
      data: { source_type: sourceType, source_id: sourceId },
    });
    this.roomRevision++;
    await this.liveRooms.ready;
    this.liveRooms.upsertRoom(result.room);
    if (sourceType === "category") {
      this.channels = this.channels.map((channel) =>
        channel.category_id === Number(sourceId)
          ? { ...channel, room: result.room }
          : channel
      );
    }
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
    this.roomRevision++;
    const room = this.liveRooms.roomById(message.room_id);
    if (room) {
      this.liveWebrtc.leave(room, { skipServer: true });
      this.liveRooms.handleDirectoryEvent({ type: "destroyed", room });
    }
    await this.refresh();
  }
}
