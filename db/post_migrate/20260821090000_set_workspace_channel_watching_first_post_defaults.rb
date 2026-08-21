# frozen_string_literal: true

class SetWorkspaceChannelWatchingFirstPostDefaults < ActiveRecord::Migration[8.0]
  # NotificationLevels.all[:watching_first_post]
  WATCHING_FIRST_POST = 4

  def up
    return if !table_exists?(:categories)
    return if !table_exists?(:category_custom_fields)
    return if !table_exists?(:groups)
    return if !table_exists?(:group_users)
    return if !table_exists?(:group_category_notification_defaults)
    return if !table_exists?(:category_users)

    execute <<~SQL
      WITH workspace_channels AS (
        SELECT c.id AS category_id,
               g.id AS group_id
          FROM categories c
          JOIN category_custom_fields kind
            ON kind.category_id = c.id
           AND kind.name = 'workspace_kind'
           AND kind.value = 'channel'
          JOIN category_custom_fields group_reference
            ON group_reference.category_id = c.id
           AND group_reference.name = 'workspace_group_id'
          JOIN groups g
            ON g.id = CASE
                        WHEN group_reference.value ~ '^[1-9][0-9]*$'
                        THEN group_reference.value::integer
                      END
      )
      INSERT INTO group_category_notification_defaults
        (group_id, category_id, notification_level)
      SELECT group_id, category_id, #{WATCHING_FIRST_POST}
        FROM workspace_channels
      ON CONFLICT (group_id, category_id) DO UPDATE
        SET notification_level = EXCLUDED.notification_level
    SQL

    execute <<~SQL
      WITH workspace_channels AS (
        SELECT c.id AS category_id,
               g.id AS group_id
          FROM categories c
          JOIN category_custom_fields kind
            ON kind.category_id = c.id
           AND kind.name = 'workspace_kind'
           AND kind.value = 'channel'
          JOIN category_custom_fields group_reference
            ON group_reference.category_id = c.id
           AND group_reference.name = 'workspace_group_id'
          JOIN groups g
            ON g.id = CASE
                        WHEN group_reference.value ~ '^[1-9][0-9]*$'
                        THEN group_reference.value::integer
                      END
      )
      INSERT INTO category_users (category_id, user_id, notification_level)
      SELECT workspace_channels.category_id,
             group_users.user_id,
             #{WATCHING_FIRST_POST}
        FROM workspace_channels
        JOIN group_users
          ON group_users.group_id = workspace_channels.group_id
        LEFT JOIN category_users
          ON category_users.category_id = workspace_channels.category_id
         AND category_users.user_id = group_users.user_id
       WHERE category_users.id IS NULL
      ON CONFLICT (category_id, user_id) DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
