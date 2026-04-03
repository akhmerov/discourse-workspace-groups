import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default class WorkspaceOverviewChannelCard extends Component {
  get channel() {
    return this.args.channel;
  }

  get hasActions() {
    return (
      this.channel?.can_join ||
      this.channel?.can_leave ||
      this.channel?.can_manage_access ||
      this.channel?.can_archive ||
      this.channel?.can_unarchive
    );
  }

  <template>
    <article class="workspace-groups-overview__card">
      <div class="workspace-groups-overview__card-header">
        <div>
          <div class="workspace-groups-overview__heading">
            <h3>
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

          {{#if this.channel.description}}
            <p class="workspace-groups-overview__channel-description">
              {{this.channel.description}}
            </p>
          {{/if}}
        </div>

        <div class="workspace-groups-overview__card-meta">
          <div class="workspace-groups-overview__badges">
            <span class="workspace-groups-overview__visibility">
              {{icon (if (eq this.channel.visibility "private") "lock" "globe")}}
              {{i18n (if
                (eq this.channel.visibility "private")
                "discourse_workspace_groups.visibility_private"
                "discourse_workspace_groups.visibility_public"
              )}}
            </span>

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
                  @label="discourse_workspace_groups.join_channel"
                  class="btn-primary btn-small workspace-groups-overview__membership-button"
                  @disabled={{this.channel.is_pending}}
                />
              {{else if this.channel.can_leave}}
                <DButton
                  @action={{fn @onLeave this.channel}}
                  @label="discourse_workspace_groups.leave_channel"
                  class="btn-default btn-small workspace-groups-overview__membership-button"
                  @disabled={{this.channel.is_pending}}
                />
              {{/if}}

              {{#if this.channel.can_manage_access}}
                <DButton
                  @action={{fn @onManageAccess this.channel}}
                  @label="discourse_workspace_groups.manage_access"
                  class="btn-default btn-small workspace-groups-overview__membership-button"
                  @disabled={{this.channel.is_pending}}
                />
              {{/if}}

              {{#if this.channel.can_archive}}
                <DButton
                  @action={{fn @onArchive this.channel}}
                  @label="discourse_workspace_groups.archive_channel"
                  class="btn-default btn-small workspace-groups-overview__membership-button"
                  @disabled={{this.channel.is_pending}}
                />
              {{else if this.channel.can_unarchive}}
                <DButton
                  @action={{fn @onUnarchive this.channel}}
                  @label="discourse_workspace_groups.unarchive_channel"
                  class="btn-default btn-small workspace-groups-overview__membership-button"
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
