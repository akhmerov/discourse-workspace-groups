# discourse-workspace-groups

`discourse-workspace-groups` is a Discourse plugin that models chat-first teams and channels on top of native Discourse categories, groups, and chat channels.

It is designed for deployments where users think in terms of a team workspace with many channels, but the implementation should still reuse Discourse primitives for permissions, category metadata, and chat pairing.

## Overview

The plugin introduces two category roles:

- `workspace` root: a top-level category that represents a team or workspace
- `workspace channel`: a subcategory under that root that represents a channel

Each workspace and channel gets an associated Discourse group. Those groups remain the source of truth for access control, ownership, and membership management.

Chat integration is category-backed:

- a channel category can have a paired Discourse Chat channel
- category permissions remain the permission source
- the UI can present the channel as chat-first, topics-first, or both

## Current behavior

### Workspace roots

Workspace roots add:

- an `Overview` page for browsing and managing channels
- workspace settings for:
  - description
  - public/private workspace access
  - whether ordinary members can create channels
  - whether ordinary members can create private channels
  - auto-join channels for new workspace members
- a workspace-aware team sidebar

### Workspace channels

Workspace channels support:

- public and private visibility
- manager-controlled membership for private channels
- channel settings for name, description, visibility, archive state, and mode
- archive and unarchive behavior

Each channel can operate in one of three modes:

- `both`: topics and chat are both available
- `chat_only`: category remains the ACL object, but ordinary users cannot create new topics and the channel is treated as chat-first
- `category_only`: the paired chat channel is closed and the category becomes topics-only

### Sidebar and overview behavior

The plugin provides a separate workspace/team sidebar and overview UI so users can work with channels without being exposed to raw backing categories all the time.

Current UX includes:

- workspace overview as the default landing view for workspace root categories
- join/leave actions on overview cards
- icon-based visibility and action affordances
- muted channels dimmed and sorted to the bottom in the workspace sidebar
- archived channels hidden from the initial overview payload and loaded lazily

## Settings

Plugin settings currently exposed through Discourse site settings:

- `discourse_workspace_groups_enabled`
- `discourse_workspace_groups_members_can_create_channels`

Per-workspace settings are stored as category custom fields rather than global site settings.

## Routes and API surface

The plugin adds:

- workspace overview page route:
  - `/c/<workspace-slug>/<id>/overview`
- JSON endpoints under:
  - `/workspace-groups/workspaces/:id`
  - `/workspace-groups/workspaces/:id/channels`
  - `/workspace-groups/workspaces/:id/channels/:channel_id`
  - related membership, access, and archive routes

The primary controller is:

- [`app/controllers/discourse_workspace_groups/workspaces_controller.rb`](./app/controllers/discourse_workspace_groups/workspaces_controller.rb)

## Main implementation pieces

Core service objects:

- [`lib/discourse_workspace_groups/ensure_workspace.rb`](./lib/discourse_workspace_groups/ensure_workspace.rb)
- [`lib/discourse_workspace_groups/create_channel.rb`](./lib/discourse_workspace_groups/create_channel.rb)
- [`lib/discourse_workspace_groups/update_workspace.rb`](./lib/discourse_workspace_groups/update_workspace.rb)
- [`lib/discourse_workspace_groups/update_channel.rb`](./lib/discourse_workspace_groups/update_channel.rb)
- [`lib/discourse_workspace_groups/join_channel.rb`](./lib/discourse_workspace_groups/join_channel.rb)
- [`lib/discourse_workspace_groups/leave_channel.rb`](./lib/discourse_workspace_groups/leave_channel.rb)
- [`lib/discourse_workspace_groups/set_channel_archive_state.rb`](./lib/discourse_workspace_groups/set_channel_archive_state.rb)
- [`lib/discourse_workspace_groups/sync_category_chat_channel.rb`](./lib/discourse_workspace_groups/sync_category_chat_channel.rb)

The plugin’s custom fields and permission helpers are declared in:

- [`plugin.rb`](./plugin.rb)

## Development notes

This repo is intended to be used as a standalone plugin repo and as a submodule inside the larger Discourse checkout:

- `plugins/discourse-workspace-groups`

Typical local workflow:

1. Edit this plugin repo.
2. Sync it into the running Discourse checkout if needed.
3. Restart the dev app or let the frontend reload.
4. Verify behavior in the live overview/sidebar flows.

Focused backend verification usually lives in:

- request specs for the workspace controller
- service specs for channel/workspace lifecycle

## Limitations

This plugin is still a product prototype. Important current constraints:

- access control is category-backed by design
- chat-only behavior hides or suppresses topic affordances, but the backing category still exists
- topic/forum behavior and chat behavior are intentionally mixed in some places because they share the same underlying category
- the frontend surface is specialized for workspace use, not a drop-in replacement for all core Discourse category flows

## License

This plugin is distributed under the MIT License. See [LICENSE](./LICENSE).
