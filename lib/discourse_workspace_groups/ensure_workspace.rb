# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class EnsureWorkspace
    attr_reader :category, :user

    def initialize(category:, user:)
      @category = category
      @user = user
    end

    def call
      raise Discourse::InvalidParameters.new(:category_id) if category.blank?
      raise Discourse::InvalidAccess unless category.parent_category_id.blank?
      raise Discourse::InvalidParameters.new(:subcategories) if category.subcategories.exists?

      workspace_group = ensure_workspace_group

      category.custom_fields[WORKSPACE_ENABLED] = true
      category.custom_fields[WORKSPACE_KIND] = WORKSPACE_KIND_ROOT
      category.custom_fields[WORKSPACE_GROUP_ID] = workspace_group.id
      category.set_permissions(root_permissions(workspace_group))
      category.save!

      category
    end

    private

    def ensure_workspace_group
      group = category.workspace_group

      if group.blank?
        group_name = DiscourseWorkspaceGroups.workspace_group_name(category)
        group =
          Group.find_by(name: group_name) ||
            Group.create!(
              name: group_name,
              full_name: category.name,
              visibility_level: Group.visibility_levels[:members],
              members_visibility_level: Group.visibility_levels[:members],
              mentionable_level: Group::ALIAS_LEVELS[:nobody],
              messageable_level: Group::ALIAS_LEVELS[:nobody],
            )
      else
        group.update!(full_name: category.name)
      end

      group.custom_fields["workspace_category_id"] = category.id
      group.custom_fields["workspace_kind"] = WORKSPACE_KIND_ROOT
      group.save!

      ensure_group_owner(group, user)
      group
    end

    def ensure_group_owner(group, owner)
      return if owner.blank?

      group.add(owner) if !group.users.exists?(id: owner.id)
      group.group_users.where(user_id: owner.id).update_all(owner: true)
    end

    def root_permissions(workspace_group)
      permissions = { workspace_group.id => :full }

      category
        .subcategories
        .select(&:workspace_channel?)
        .select { |child| child.workspace_visibility == VISIBILITY_PRIVATE }
        .map(&:workspace_group_id)
        .compact
        .each { |group_id| permissions[group_id] = :full }

      permissions
    end
  end
end
