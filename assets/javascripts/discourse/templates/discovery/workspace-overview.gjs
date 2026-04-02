import { fn } from "@ember/helper";
import DButton from "discourse/components/d-button";
import Layout from "discourse/components/discovery/layout";
import Navigation from "discourse/components/discovery/navigation";
import icon from "discourse/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

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
        <header class="workspace-groups-overview__header">
          <h2>{{i18n "discourse_workspace_groups.overview_heading"}}</h2>
          <p class="workspace-groups-overview__description">
            {{i18n "discourse_workspace_groups.overview_description"}}
          </p>
        </header>

        {{#if @controller.model.channels.length}}
          <div class="workspace-groups-overview__channels">
            {{#each @controller.model.channels as |channel|}}
              <article class="workspace-groups-overview__card">
                <div class="workspace-groups-overview__card-header">
                  <div>
                    <div class="workspace-groups-overview__heading">
                      <h3>
                        {{#if channel.can_open_topics}}
                          <a
                            href={{channel.topics_url}}
                            class="workspace-groups-overview__channel-link"
                          >
                            {{channel.name}}
                          </a>
                        {{else}}
                          <span class="workspace-groups-overview__channel-name">
                            {{channel.name}}
                          </span>
                        {{/if}}
                      </h3>

                      {{#if channel.can_view_members}}
                        <a
                          href={{channel.members_url}}
                          class="workspace-groups-overview__membership workspace-groups-overview__membership-link"
                        >
                          {{icon "user"}}
                          <span>
                            {{i18n
                              "discourse_workspace_groups.member_count"
                              count=channel.member_count
                            }}
                          </span>
                        </a>
                      {{else}}
                        <span class="workspace-groups-overview__membership">
                          {{icon "user"}}
                          <span>
                            {{i18n
                              "discourse_workspace_groups.member_count"
                              count=channel.member_count
                            }}
                          </span>
                        </span>
                      {{/if}}
                    </div>

                    {{#if channel.description}}
                      <p class="workspace-groups-overview__channel-description">
                        {{channel.description}}
                      </p>
                    {{/if}}
                  </div>

                  <div class="workspace-groups-overview__card-meta">
                    <span class="workspace-groups-overview__visibility">
                      {{icon (if
                        (eq channel.visibility "private")
                        "lock"
                        "globe"
                      )}}
                      {{i18n (if
                        (eq channel.visibility "private")
                        "discourse_workspace_groups.visibility_private"
                        "discourse_workspace_groups.visibility_public"
                      )}}
                    </span>

                    {{#if channel.can_join}}
                      <DButton
                        @action={{fn @controller.joinChannel channel}}
                        @label="discourse_workspace_groups.join_channel"
                        class="btn-primary btn-small workspace-groups-overview__membership-button"
                        @disabled={{channel.is_pending}}
                      />
                    {{else if channel.can_leave}}
                      <DButton
                        @action={{fn @controller.leaveChannel channel}}
                        @label="discourse_workspace_groups.leave_channel"
                        class="btn-default btn-small workspace-groups-overview__membership-button"
                        @disabled={{channel.is_pending}}
                      />
                    {{/if}}
                  </div>
                </div>
              </article>
            {{/each}}
          </div>
        {{else}}
          <p class="workspace-groups-overview__empty">
            {{i18n "discourse_workspace_groups.overview_empty"}}
          </p>
        {{/if}}
      </section>
    </:list>
  </Layout>
</template>;
