# frozen_string_literal: true

class SyncWorkspaceChatChannelEmojis < ActiveRecord::Migration[8.0]
  # Category.style_types[:emoji]
  EMOJI_STYLE_TYPE = 2

  def up
    return if !table_exists?(:categories)
    return if !table_exists?(:category_custom_fields)
    return if !table_exists?(:chat_channels)
    return if !column_exists?(:categories, :style_type)
    return if !column_exists?(:categories, :emoji)
    return if !column_exists?(:chat_channels, :emoji)

    DB.exec(<<~SQL)
      UPDATE chat_channels cc
         SET emoji = category_icons.desired_emoji,
             updated_at = CURRENT_TIMESTAMP
        FROM (
          SELECT c.id,
                 CASE
                   WHEN c.style_type = #{EMOJI_STYLE_TYPE} THEN NULLIF(c.emoji, '')
                   ELSE NULL
                 END AS desired_emoji
            FROM categories c
            JOIN category_custom_fields cf
              ON cf.category_id = c.id
             AND cf.name = 'workspace_kind'
             AND cf.value = 'channel'
        ) category_icons
       WHERE cc.chatable_type = 'Category'
         AND cc.type = 'CategoryChannel'
         AND cc.chatable_id = category_icons.id
         AND cc.emoji IS DISTINCT FROM category_icons.desired_emoji
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
