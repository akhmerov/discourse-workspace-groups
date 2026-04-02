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
                    <h3>
                      <a
                        href={{channel.topics_url}}
                        class="workspace-groups-overview__channel-link"
                      >
                        {{channel.name}}
                      </a>
                    </h3>

                    {{#if channel.description}}
                      <p class="workspace-groups-overview__channel-description">
                        {{channel.description}}
                      </p>
                    {{/if}}
                  </div>

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
                </div>

                <div class="workspace-groups-overview__actions">
                  <a href={{channel.topics_url}} class="btn btn-default btn-small">
                    {{icon "list"}}
                    <span>{{i18n "discourse_workspace_groups.open_topics"}}</span>
                  </a>

                  {{#if channel.chat_url}}
                    <a href={{channel.chat_url}} class="btn btn-default btn-small">
                      {{icon "d-chat"}}
                      <span>{{i18n "discourse_workspace_groups.open_chat"}}</span>
                    </a>
                  {{/if}}
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
