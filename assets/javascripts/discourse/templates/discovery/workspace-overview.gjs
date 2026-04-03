import { trustHTML } from "@ember/template";
import DButton from "discourse/components/d-button";
import DecoratedHtml from "discourse/components/decorated-html";
import Layout from "discourse/components/discovery/layout";
import Navigation from "discourse/components/discovery/navigation";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";
import WorkspaceOverviewChannelCard from "../../components/workspace-overview-channel-card";

export default <template>
  <Layout
    @model={{@controller.model}}
    @createTopicDisabled={{@controller.createTopicDisabled}}
    @listClass="workspace-groups-overview-page"
  >
    <:navigation>
      <Navigation
        @category={{@controller.model.category}}
        @filterType={{@controller.model.filterType}}
        @noSubcategories={{@controller.model.noSubcategories}}
        @createTopic={{@controller.createTopic}}
        @createTopicDisabled={{@controller.createTopicDisabled}}
        @canBulkSelect={{false}}
      />
    </:navigation>

    <:list>
      <section class="workspace-groups-overview">
        <header class="workspace-groups-overview__team">
          <div class="workspace-groups-overview__team-heading">
            <h1 class="workspace-groups-overview__team-name">{{@controller.teamName}}</h1>

            {{#if @controller.teamCanViewMembers}}
              <a
                href={{@controller.teamMembersUrl}}
                class="workspace-groups-overview__membership workspace-groups-overview__membership-link"
              >
                {{icon "user"}}
                <span>
                  {{i18n
                    "discourse_workspace_groups.member_count"
                    count=@controller.teamMemberCount
                  }}
                </span>
              </a>
            {{else}}
              <span class="workspace-groups-overview__membership">
                {{icon "user"}}
                <span>
                  {{i18n
                    "discourse_workspace_groups.member_count"
                    count=@controller.teamMemberCount
                  }}
                </span>
              </span>
            {{/if}}
          </div>

          {{#if @controller.teamAboutCooked}}
            <DecoratedHtml
              @html={{trustHTML @controller.teamAboutCooked}}
              @className="cooked workspace-groups-overview__team-about"
            />
          {{/if}}
        </header>

        <div class="workspace-groups-overview__header">
          <div class="workspace-groups-overview__header-copy">
            <div class="workspace-groups-overview__title-row">
              <h2>{{i18n "discourse_workspace_groups.overview_heading"}}</h2>

              {{#if @controller.canCreateChannel}}
                <DButton
                  @action={{@controller.openCreateChannelModal}}
                  @icon="plus"
                  @label="discourse_workspace_groups.create"
                  @title="discourse_workspace_groups.create_channel_title"
                  class="btn-primary btn-small workspace-groups-overview__create-channel-button"
                />
              {{/if}}
            </div>

            <p class="workspace-groups-overview__description">
              {{i18n "discourse_workspace_groups.overview_description"}}
            </p>
          </div>
        </div>

        {{#if @controller.activeChannels.length}}
          <div class="workspace-groups-overview__channels">
            {{#each @controller.activeChannels as |channel|}}
              <WorkspaceOverviewChannelCard
                @channel={{channel}}
                @onJoin={{@controller.joinChannel}}
                @onLeave={{@controller.leaveChannel}}
                @onManageAccess={{@controller.openManageAccessModal}}
                @onArchive={{@controller.archiveChannel}}
                @onUnarchive={{@controller.unarchiveChannel}}
              />
            {{/each}}
          </div>
        {{else if @controller.archivedChannels.length}}
          <p class="workspace-groups-overview__empty">
            {{i18n "discourse_workspace_groups.overview_active_empty"}}
          </p>
        {{else}}
          <p class="workspace-groups-overview__empty">
            {{i18n "discourse_workspace_groups.overview_empty"}}
          </p>
        {{/if}}

        {{#if @controller.archivedChannels.length}}
          <details class="workspace-groups-overview__archived">
            <summary class="workspace-groups-overview__archived-summary">
              {{i18n
                "discourse_workspace_groups.archived_channels_summary"
                count=@controller.archivedChannels.length
              }}
            </summary>

            <div class="workspace-groups-overview__channels workspace-groups-overview__channels--archived">
              {{#each @controller.archivedChannels as |channel|}}
                <WorkspaceOverviewChannelCard
                  @channel={{channel}}
                  @onJoin={{@controller.joinChannel}}
                  @onLeave={{@controller.leaveChannel}}
                  @onManageAccess={{@controller.openManageAccessModal}}
                  @onArchive={{@controller.archiveChannel}}
                  @onUnarchive={{@controller.unarchiveChannel}}
                />
              {{/each}}
            </div>
          </details>
        {{/if}}
      </section>
    </:list>
  </Layout>
</template>;
