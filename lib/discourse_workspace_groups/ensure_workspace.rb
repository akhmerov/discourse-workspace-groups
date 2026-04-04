# frozen_string_literal: true

module ::DiscourseWorkspaceGroups
  class EnsureWorkspace
    attr_reader :category, :user, :public_read

    def initialize(category:, user:, public_read: false)
      @category = category
      @user = user
      @public_read = public_read
    end

    def call
      raise Discourse::InvalidParameters.new(:category_id) if category.blank?
      raise Discourse::InvalidAccess unless category.parent_category_id.blank?
      raise Discourse::InvalidParameters.new(:subcategories) if category.subcategories.exists?

      workspace_group = ensure_workspace_group

      category.custom_fields[WORKSPACE_ENABLED] = true
      category.custom_fields[WORKSPACE_KIND] = WORKSPACE_KIND_ROOT
      category.custom_fields[WORKSPACE_GROUP_ID] = workspace_group.id
      category.custom_fields[WORKSPACE_ROOT_PUBLIC_READ] = public_read
      category.set_permissions(root_permissions(workspace_group))
      category.save!

      category
    end

    private

    def ensure_workspace_group
      group = category.workspace_group
      group_name = DiscourseWorkspaceGroups.workspace_group_name(category)

      if group.blank?
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
      end

      group.update!(name: group_name, full_name: category.name)

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
      DiscourseWorkspaceGroups.workspace_root_permissions(
        workspace_group,
        DiscourseWorkspaceGroups.workspace_channel_group_ids(category),
        public_read: public_read,
      )
    end
  end
end
