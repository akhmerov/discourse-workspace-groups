import { trustHTML } from "@ember/template";
import Component from "@glimmer/component";
import DecoratedHtml from "discourse/components/decorated-html";
import { fn } from "@ember/helper";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class WorkspaceOverviewChannelCard extends Component {
  get channel() {
    return this.args.channel;
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
      this.channel?.can_unarchive
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

  <template>
    <article class="workspace-groups-overview__card">
      <div class="workspace-groups-overview__card-header">
        <div>
          <div class="workspace-groups-overview__heading">
            <h3>
              <span
                class="workspace-groups-overview__visibility workspace-groups-overview__visibility--title"
                title={{this.visibilityLabel}}
                aria-label={{this.visibilityLabel}}
              >
                {{icon this.visibilityIcon}}
              </span>

              {{#if this.channel.can_open_topics}}
                <a
                  href={{this.channel.topics_url}}
                  class="workspace-groups-overview__channel-link"
                >
                  {{this.channel.name}}
                </a>
              {{else}}
                <span class="workspace-groups-overview__channel-name">
                  {{this.channel.name}}
                </span>
              {{/if}}
            </h3>

            {{#if this.channel.can_view_members}}
              <a
                href={{this.channel.members_url}}
                class="workspace-groups-overview__membership workspace-groups-overview__membership-link"
              >
                {{icon "user"}}
                <span>
                  {{i18n
                    "discourse_workspace_groups.member_count"
                    count=this.channel.member_count
                  }}
                </span>
              </a>
            {{else}}
              <span class="workspace-groups-overview__membership">
                {{icon "user"}}
                <span>
                  {{i18n
                    "discourse_workspace_groups.member_count"
                    count=this.channel.member_count
                  }}
                </span>
              </span>
            {{/if}}
          </div>

          {{#if this.descriptionCooked}}
            <DecoratedHtml
              @html={{trustHTML this.descriptionCooked}}
              @className="cooked workspace-groups-overview__channel-description"
            />
          {{else if this.channel.description}}
            <p class="workspace-groups-overview__channel-description">
              {{this.channel.description}}
            </p>
          {{/if}}
        </div>

        <div class="workspace-groups-overview__card-meta">
          <div class="workspace-groups-overview__badges">
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
                  @action={{fn @onJoin this.channel}}
                  @icon={{this.membershipActionIcon}}
                  @title={{this.membershipActionLabel}}
                  @ariaLabel={{this.membershipActionLabel}}
                  class="btn-primary btn-small workspace-groups-overview__membership-button workspace-groups-overview__membership-button--icon"
                  @disabled={{this.channel.is_pending}}
                />
              {{else if this.channel.can_leave}}
                <DButton
                  @action={{fn @onLeave this.channel}}
                  @icon={{this.membershipActionIcon}}
                  @title={{this.membershipActionLabel}}
                  @ariaLabel={{this.membershipActionLabel}}
                  class="btn-default btn-small workspace-groups-overview__membership-button workspace-groups-overview__membership-button--icon"
                  @disabled={{this.channel.is_pending}}
                />
              {{/if}}

              {{#if this.canManageChannel}}
                <DButton
                  @action={{fn @onOpenSettings this.channel}}
                  @icon="wrench"
                  @title="discourse_workspace_groups.channel_settings"
                  @ariaLabel="discourse_workspace_groups.channel_settings"
                  class="btn-default btn-small workspace-groups-overview__membership-button workspace-groups-overview__membership-button--icon"
                  @disabled={{this.channel.is_pending}}
                />
              {{/if}}
            </div>
          {{/if}}
        </div>
      </div>
    </article>
  </template>
}
