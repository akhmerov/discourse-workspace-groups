# discourse-workspace-groups

Prototype Discourse plugin for modeling isolated teams and channels on top of categories, groups, and chat channels.

## Warning

This plugin was developed entirely by an agent. It has not gone through a conventional human-led engineering, security, or product review process. Review, test, and use it at your own risk.

## What It Does

- Treats selected top-level categories as team workspaces
- Treats subcategories as channels, each paired with a category chat channel
- Adds a team overview page for channel discovery and management
- Supports public and private channels
- Supports joining and leaving channels
- Supports guest access to specific channels without full team membership
- Supports channel archiving, with archived channels becoming read-only
- Adds a workspace-oriented team sidebar experience

## Current Status

This is a prototype. It is useful for experimentation and local development, but it should not be assumed production-ready.

## Development

This plugin has been developed against a local Discourse dev instance. In this workspace, the standalone plugin repo is used as a submodule from:

- `plugins/discourse-workspace-groups`

Typical local workflow in this repo:

1. Edit the standalone plugin repo.
2. Update the submodule checkout in the Discourse repo.
3. Restart or refresh the local dev instance as needed.
4. Verify in the running app.

## License

This plugin is distributed under the GNU General Public License, version 2 only. See [LICENSE](./LICENSE).
