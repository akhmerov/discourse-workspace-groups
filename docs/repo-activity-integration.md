# Repository activity integration

`discourse-repo-activity` owns receive-only GitHub/GitLab webhook ingestion,
connections, bot announcements and the chat header pill. It works independently
of workspace groups and never changes the sidebar.

Workspace groups extends the single `repo_activity_channel_manager` modifier
with `can_manage_workspace_channel?`. Existing channel owners gain repository
management; ordinary members with the broader channel-settings editing policy
do not. Admins and moderators retain the feature plugin's default permission.
All requests also require the live chat visibility check.

The workspace channel settings modal exposes **Repositories** for managers of
channels with paired chat. Its optional `repo-activity` service opens the feature
plugin's management modal. With the feature plugin absent or disabled the entry
is omitted. No forge credentials or connection data belong in workspace groups.
