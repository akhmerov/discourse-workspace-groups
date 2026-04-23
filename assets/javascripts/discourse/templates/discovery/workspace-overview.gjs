import { on } from "@ember/modifier";
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
            <div class="workspace-groups-overview__heading workspace-groups-overview__heading--team">
              <h1 class="workspace-groups-overview__team-name">
                <span
                  class="workspace-groups-overview__visibility workspace-groups-overview__visibility--title"
                  title={{@controller.teamVisibilityLabel}}
                  aria-label={{@controller.teamVisibilityLabel}}
                >
                  {{icon @controller.teamVisibilityIcon}}
                </span>
                <span>{{@controller.teamName}}</span>
              </h1>

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

            <div class="workspace-groups-overview__team-actions">
              {{#if @controller.canManageWorkspace}}
                <DButton
                  @action={{@controller.openWorkspaceSettingsModal}}
                  @icon="wrench"
                  @title="discourse_workspace_groups.workspace_settings"
                  @ariaLabel="discourse_workspace_groups.workspace_settings"
                  class="btn-default btn-small workspace-groups-overview__settings-button"
                />
              {{/if}}
            </div>
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
                @onOpenSettings={{@controller.openChannelSettingsModal}}
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

        {{#if @controller.hasArchivedChannels}}
          <details
            class="workspace-groups-overview__archived"
            {{on "toggle" @controller.loadArchivedChannels}}
          >
            <summary class="workspace-groups-overview__archived-summary">
              {{i18n
                "discourse_workspace_groups.archived_channels_summary"
                count=@controller.archivedChannelCount
              }}
            </summary>

            {{#if @controller.model.archivedChannelsLoading}}
              <p class="workspace-groups-overview__archived-loading">
                {{i18n "loading"}}
              </p>
            {{else if @controller.model.archivedChannelsLoaded}}
              <div class="workspace-groups-overview__channels workspace-groups-overview__channels--archived">
                {{#each @controller.archivedChannels as |channel|}}
                  <WorkspaceOverviewChannelCard
                    @channel={{channel}}
                    @onJoin={{@controller.joinChannel}}
                    @onLeave={{@controller.leaveChannel}}
                    @onOpenSettings={{@controller.openChannelSettingsModal}}
                  />
                {{/each}}
              </div>
            {{/if}}
          </details>
        {{/if}}
      </section>
    </:list>
  </Layout>
</template>;
