# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  # Keeps chat's quick channel palette (Ctrl-K) about things people choose to open.
  module ChatableSearch
    CATEGORY_CHANNEL_CANDIDATES = 50

    private

    # Team and channel groups are membership plumbing, not audiences to message.
    def search_groups(params, guardian)
      groups = super
      return groups if !SiteSetting.discourse_workspace_groups_enabled

      groups.where.not(
        id: GroupCustomField.where(name: WORKSPACE_KIND).select(:group_id),
      )
    end

    # Chat slugs of team channels start with the team slug, so any fragment of a team name
    # matched every channel in that team and crowded out channels matching by name.
    def search_category_channels(params, guardian)
      return super if !SiteSetting.discourse_workspace_groups_enabled || params.term.blank?

      channels =
        ::Chat::ChannelFetcher.secured_public_channel_search(
          guardian,
          status: :open,
          filter: params.term,
          filter_on_category_name: false,
          limit: CATEGORY_CHANNEL_CANDIDATES,
        ).to_a

      team_slugs = team_slugs_by_channel_category_id(channels)
      channels
        .select { |channel| channel_matches_term?(channel, params.term, team_slugs[channel.chatable_id]) }
        .first(self.class::SEARCH_RESULT_LIMIT)
    end

    def team_slugs_by_channel_category_id(channels)
      categories = channels.map(&:chatable).select { |chatable| chatable.is_a?(Category) }
      Category.preload_custom_fields(categories, Site.preloaded_category_custom_fields)
      team_categories = categories.select(&:workspace_channel?)
      parents = Category.where(id: team_categories.map(&:parent_category_id)).pluck(:id, :slug).to_h

      team_categories.to_h { |category| [category.id, parents[category.parent_category_id]] }
    end

    def channel_matches_term?(channel, term, team_slug)
      return true if team_slug.blank?

      term = term.downcase
      return true if (channel.name.presence || channel.chatable&.name).to_s.downcase.include?(term)

      channel.slug.to_s.downcase.delete_prefix("#{team_slug.downcase}-").include?(term)
    end
  end
end
