import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import DButton from "discourse/ui-kit/d-button";
import DDecoratedHtml from "discourse/ui-kit/d-decorated-html";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { isEventCategory } from "../lib/workspace-event-categories";

export default class WorkspaceOverviewChannelCard extends Component {
  @service siteSettings;

  get channel() {
    return this.args.channel;
  }

  get chatPath() {
    if (!this.channel?.chat_channel_id) {
      return null;
    }

    return `/chat/c/${this.channel.chat_channel_slug || this.channel.chat_channel?.slug || "-"}/${this.channel.chat_channel_id}`;
  }

  get titleHref() {
    if (!this.canOpenChannel) {
      return null;
    }

    if (this.channel?.mode === "chat_only" && this.chatPath) {
      return this.chatPath;
    }

    if (this.channel?.can_open_topics) {
      return this.channel.topics_url;
    }

    return null;
  }

  get canOpenChannel() {
    return Boolean(this.channel?.joined || this.channel?.can_open_topics);
  }

  get descriptionCooked() {
    return this.channel?.description_cooked
      ?.replace(/\|\s*<br\s*\/?>\s*/gi, "| ")
      ?.replace(/\s*<br\s*\/?>\s*\|/gi, " |");
  }

  get hasActions() {
    return (
      this.channel?.can_join ||
      this.channel?.can_leave ||
      this.channel?.can_archive ||
      this.channel?.can_unarchive ||
      this.channel?.can_view_members
    );
  }

  get visibilityIcon() {
    return this.channel?.visibility === "private" ? "lock" : "globe";
  }

  get visibilityLabel() {
    return i18n(
      this.channel?.visibility === "private"
        ? "discourse_workspace_groups.visibility_private"
        : "discourse_workspace_groups.visibility_public"
    );
  }

  get membershipActionLabel() {
    return this.channel?.can_join
      ? "discourse_workspace_groups.join_channel"
      : "discourse_workspace_groups.leave_channel";
  }

  get membershipActionIcon() {
    return this.channel?.can_join ? "right-to-bracket" : "right-from-bracket";
  }

  get canManageChannel() {
    return this.channel?.can_archive || this.channel?.can_unarchive;
  }

  get lastActivityDate() {
    if (!this.channel?.last_activity_at) {
      return null;
    }

    return dFormatDate(this.channel.last_activity_at, {
      leaveAgo: true,
    });
  }

  get showsTopicsIcon() {
    return this.channel?.mode !== "chat_only";
  }

  get topicsIcon() {
    return isEventCategory(this.siteSettings, this.channel)
      ? "calendar-day"
      : "list";
  }

  get showsChatIcon() {
    return this.channel?.mode !== "category_only";
  }

  get showsVoiceIcon() {
    return (
      this.siteSettings.voice_enabled &&
      this.channel?.voice_enabled &&
      !this.channel?.archived
    );
  }

  get voiceAccessLabel() {
    return this.channel?.can_join
      ? "discourse_workspace_groups.voice.join_channel_first"
      : "discourse_workspace_groups.voice.members_only";
  }

  get topicsHref() {
    if (!this.showsTopicsIcon || !this.channel?.can_open_topics) {
      return null;
    }

    return this.channel.topics_url;
  }

  get chatHref() {
    if (!this.showsChatIcon || !this.canOpenChannel) {
      return null;
    }

    return this.chatPath;
  }

  <template>
    <article class="workspace-groups-overview__card">
      <div class="workspace-groups-overview__card-header">
        <div>
          <div class="workspace-groups-overview__heading">
            <h3>
              <span
                aria-label={{this.visibilityLabel}}
                class="workspace-groups-overview__visibility workspace-groups-overview__visibility--title"
                title={{this.visibilityLabel}}
              >
                {{dIcon this.visibilityIcon}}
              </span>

              {{#if this.titleHref}}
                <a
                  class="workspace-groups-overview__channel-link"
                  href={{this.titleHref}}
                >
                  {{this.channel.name}}
                </a>
              {{else if this.channel.can_join}}
                <button
                  class="workspace-groups-overview__channel-link workspace-groups-overview__channel-link-button"
                  disabled={{this.channel.is_pending}}
                  title={{i18n "discourse_workspace_groups.join_channel"}}
                  type="button"
                  {{on "click" (fn @onJoin this.channel)}}
                >
                  {{this.channel.name}}
                </button>
              {{else}}
                <span class="workspace-groups-overview__channel-name">
                  {{this.channel.name}}
                </span>
              {{/if}}
            </h3>

            <span class="workspace-groups-overview__channel-modes">
              {{#if this.showsTopicsIcon}}
                {{#if this.topicsHref}}
                  <a
                    aria-label={{i18n
                      "discourse_workspace_groups.channel_topics"
                    }}
                    class="workspace-groups-overview__channel-mode workspace-groups-overview__channel-mode-link"
                    href={{this.topicsHref}}
                    title={{i18n "discourse_workspace_groups.channel_topics"}}
                  >
                    {{dIcon this.topicsIcon}}
                  </a>
                {{else}}
                  <span
                    aria-label={{i18n
                      "discourse_workspace_groups.channel_topics"
                    }}
                    class="workspace-groups-overview__channel-mode"
                    title={{i18n "discourse_workspace_groups.channel_topics"}}
                  >
                    {{dIcon this.topicsIcon}}
                  </span>
                {{/if}}
              {{/if}}

              {{#if this.showsChatIcon}}
                {{#if this.chatHref}}
                  <a
                    aria-label={{i18n
                      "discourse_workspace_groups.channel_chat"
                    }}
                    class="workspace-groups-overview__channel-mode workspace-groups-overview__channel-mode-link"
                    href={{this.chatHref}}
                    title={{i18n "discourse_workspace_groups.channel_chat"}}
                  >
                    {{dIcon "d-chat"}}
                  </a>
                {{else}}
                  <span
                    aria-label={{i18n
                      "discourse_workspace_groups.channel_chat"
                    }}
                    class="workspace-groups-overview__channel-mode"
                    title={{i18n "discourse_workspace_groups.channel_chat"}}
                  >
                    {{dIcon "d-chat"}}
                  </span>
                {{/if}}
              {{/if}}
              {{#if this.showsVoiceIcon}}
                {{#if this.channel.joined}}
                  <LinkTo
                    aria-label={{i18n "discourse_workspace_groups.voice.open"}}
                    class="workspace-groups-overview__channel-mode workspace-groups-overview__channel-mode-link workspace-groups-overview__voice"
                    title={{i18n "discourse_workspace_groups.voice.open"}}
                    @model={{this.channel.id}}
                    @route="workspace-voice.channel"
                  >
                    {{dIcon "microphone"}}
                  </LinkTo>
                {{else}}
                  <span
                    aria-label={{i18n this.voiceAccessLabel}}
                    class="workspace-groups-overview__channel-mode workspace-groups-overview__voice"
                    title={{i18n this.voiceAccessLabel}}
                  >
                    {{dIcon "microphone"}}
                  </span>
                {{/if}}
              {{/if}}
            </span>

            {{#if this.channel.can_view_members}}
              {{#if @onOpenMembers}}
                <button
                  class="workspace-groups-overview__membership workspace-groups-overview__membership-link"
                  type="button"
                  {{on "click" (fn @onOpenMembers this.channel)}}
                >
                  {{dIcon "user"}}
                  <span>
                    {{i18n
                      "discourse_workspace_groups.member_count"
                      count=this.channel.member_count
                    }}
                  </span>
                </button>
              {{else}}
                <span class="workspace-groups-overview__membership">
                  {{dIcon "user"}}
                  <span>
                    {{i18n
                      "discourse_workspace_groups.member_count"
                      count=this.channel.member_count
                    }}
                  </span>
                </span>
              {{/if}}
            {{/if}}
          </div>

          {{#if this.descriptionCooked}}
            <DDecoratedHtml
              @className="cooked workspace-groups-overview__channel-description"
              @html={{trustHTML this.descriptionCooked}}
            />
          {{else if this.channel.description}}
            <p class="workspace-groups-overview__channel-description">
              {{this.channel.description}}
            </p>
          {{/if}}
        </div>

        <div class="workspace-groups-overview__card-meta">
          <div class="workspace-groups-overview__badges">
            {{#if this.lastActivityDate}}
              <span
                class="workspace-groups-overview__activity"
                title={{i18n "discourse_workspace_groups.last_activity"}}
              >
                {{dIcon "clock"}}
                <span>{{this.lastActivityDate}}</span>
              </span>
            {{/if}}

            {{#if this.channel.archived}}
              <span class="workspace-groups-overview__state">
                {{i18n "discourse_workspace_groups.archived_channel"}}
              </span>
            {{/if}}
          </div>

          {{#if this.hasActions}}
            <div class="workspace-groups-overview__card-actions">
              {{#if this.channel.can_join}}
                <DButton
                  class="btn-primary btn-small workspace-groups-overview__membership-button workspace-groups-overview__membership-button--icon"
                  @action={{fn @onJoin this.channel}}
                  @ariaLabel={{this.membershipActionLabel}}
                  @disabled={{this.channel.is_pending}}
                  @icon={{this.membershipActionIcon}}
                  @title={{this.membershipActionLabel}}
                />
              {{else if this.channel.can_leave}}
                <DButton
                  class="btn-default btn-small workspace-groups-overview__membership-button workspace-groups-overview__membership-button--icon"
                  @action={{fn @onLeave this.channel}}
                  @ariaLabel={{this.membershipActionLabel}}
                  @disabled={{this.channel.is_pending}}
                  @icon={{this.membershipActionIcon}}
                  @title={{this.membershipActionLabel}}
                />
              {{/if}}

              {{#if this.canManageChannel}}
                <DButton
                  class="btn-default btn-small workspace-groups-overview__membership-button workspace-groups-overview__membership-button--icon"
                  @action={{fn @onOpenSettings this.channel}}
                  @ariaLabel="discourse_workspace_groups.channel_settings"
                  @disabled={{this.channel.is_pending}}
                  @icon="wrench"
                  @title="discourse_workspace_groups.channel_settings"
                />
              {{/if}}

              {{#if this.channel.can_view_members}}
                <DButton
                  class="btn-default btn-small workspace-groups-overview__membership-button workspace-groups-overview__membership-button--icon"
                  @action={{fn @onOpenMembers this.channel}}
                  @ariaLabel="discourse_workspace_groups.channel_members"
                  @disabled={{this.channel.is_pending}}
                  @icon="user"
                  @title="discourse_workspace_groups.channel_members"
                />
              {{/if}}
            </div>
          {{/if}}
        </div>
      </div>
    </article>
  </template>
}
