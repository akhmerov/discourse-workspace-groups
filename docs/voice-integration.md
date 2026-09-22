# Voice integration with workspace channels and direct messages

Status: technical proposal, 2026-09-22, updated to use one optional Voice
capability per workspace channel. Town Square supplies the common room through
the same setting. The [product analysis](voice-product-analysis.md) proposes
temporary session guests; reconcile that proposal with this draft's invitation
rules before implementation. No workspace integration has been deployed. Native
TL2 direct calls are enabled in production and sandbox.

## Product model

Workspace channels gain an **Enable voice room** setting, off by default and
editable by existing channel managers. An enabled channel exposes Join room even
when empty and shows current participants during a session. One-to-one and group
DMs expose Start call / Join call under the direct-call policy, without requiring
a workspace channel setting. One active session per conversation avoids splitting
participants when two people start at once. The native Voice widget lets
participants keep browsing while connected.

A channel room is the native Voice room carrying that channel's sessions. The
channel provides its identity, name, membership, and management. Provision the
native room on demand. Voice is independent of topics/chat mode; a topics-only
channel can enable Voice without opening its paired chat channel.

Town Square with Voice enabled provides the common room through ordinary channel
membership. Use existing channel join and auto-join mechanisms for its intended
audience. Voice does not implicitly add workspace members to Town Square or
widen the room's audience. Coffee, project, and meeting rooms use this same
setting on their respective channels. There is no separate workspace-room object
or persistent-versus-ad-hoc mode.

This is one coherent integration covering workspace channels and DMs. Testing
may proceed in steps, but DM support and privacy are part of the design and
acceptance criteria, not deferred product functionality.

## Permissions

| Conversation | Who may see and join the call | Who may start it | Management |
| --- | --- | --- | --- |
| Workspace channel | Current channel-group members with eligible accounts, while Voice is enabled | Any eligible member | Existing channel managers |
| Private workspace channel | Current private-channel members with eligible accounts, while Voice is enabled | Any eligible member | Existing private-channel managers |
| One-to-one DM | The two participants, subject to account/chat restrictions | Either participant, subject to communication preferences | Both are peers; no permanent creator privilege |
| Group DM | Current participants in that DM | Any eligible participant | Follow the DM's existing membership-management rules |

Trust level is not workspace membership. TL0/TL1 members can participate when
their channel and account permissions allow it; TL2 outsiders gain no access.
The site-wide Voice gate must admit eligible channel/DM users and retain the global
kill switch. For integrated rooms, channel authorization is authoritative.

A public workspace channel is joinable under workspace rules, not a site-public
Voice room. Join the channel first, then join the call. Publicly readable category
pages do not grant voice participation. Channel guests do not gain access to
other channels, including Town Square, merely by using Voice.

Workspace ownership must not grant membership in unjoined private channels.
Preserve the existing rule that team owners gain ownership of channels they
already belong to. A workspace role grants no ordinary access to private DMs.
Native Voice's staff override must not silently add moderators to DM calls;
any site-admin recovery remains a separate explicit administrative action.

## Calls, invitations, and notifications

Starting a workspace-channel call announces activity in that channel without
ringing the entire workspace. A one-to-one call may ring the other participant;
group DM calls notify only the DM audience and respect mute, ignore, and
do-not-disturb preferences. Existing DM membership must not bypass those
preferences when sending a ring. Joining is always explicit; opening a channel
never turns on a microphone.

Inviting means notifying an already eligible participant. Bringing an outsider
into a call requires the normal channel/DM membership operation, including its
existing access and history implications. If adding someone to a one-to-one DM
creates a new group conversation, the group gets a separate call; the private
call is not silently widened. Removed participants lose future call access even
if DM history remains readable under chat's rules.

Current channel managers can end a channel call and use native moderation tools.
Ordinary participants can mute/deafen/leave, but starting the call does not grant
permanent management or permission to edit its audience. Do not use the native
room creator field as the source of management rights. For DMs, prefer peer
behavior and existing communication controls over inventing workspace ownership.

Reuse the existing chat conversation for call messages. Do not require a new
thread or silently enable threading merely to allow a DM call. Native Voice's
optional thread-based chat panel is distinct from the conversation's existing
chat UI.

## Membership and lifecycle

Check current eligibility on protected requests: directory/room reads, joins,
heartbeats, signaling, media tokens, management actions, invites, and chat.
Copied native Voice membership rows may support native listing/broadcasts but
must never become an independent authority. Prevent native room APIs from
changing inherited visibility, membership, or chat linkage.

On removal, suspension, loss of participation rights, disabling channel Voice,
channel archive, or channel deletion, deny new access, invalidate active sessions,
remove presence, and instruct affected clients to disconnect. Remove participants from LiveKit
when applicable. Owner promotion/demotion takes effect immediately, including
native group-owner API operations that bypass model callbacks.

Peer-to-peer media does not pass through Discourse. The server can revoke its
control plane and instruct supported clients to disconnect; it cannot guarantee
termination of an established connection between modified clients. If strict
server-enforced media revocation is required, a media server is needed.

Channel renames preserve call identity. Unarchive restores eligibility from
current membership if Voice remains enabled. Re-enabling Voice preserves the
channel binding but never restores a terminated session or expired guest grant.
Missing/deleted associations fail closed. A participant who leaves a workspace loses only the calls whose underlying access they lost;
independent DMs remain governed by their own membership and account policy.

Keep the current eight-person cap and peer-to-peer transport. Recording and
transcription are separate, explicit features; linking a conversation does not
enable either or imply consent. Native direct calls are currently enabled for
TL2 users and staff. Integrating DM calls requires a deliberate access policy
consistent with the DM audience; the native rollout does not decide that policy.

## Privacy and implementation

Keep core Voice's audio/video, screenshare, and call UI. Implement workspace
integration in `discourse-workspace-groups`, with a separate module for generic
chat/DM binding so it can move upstream or to a standalone integration later.
Keep managed site configuration and rollout tooling in `discourse-config`.

Bind workspace rooms to the immutable workspace-channel category identifier,
independently of paired chat state; bind DM rooms to the immutable Chat channel
identifier. Enforce uniqueness for each binding type and identifier. Provision
through an idempotent, authorized service and serialize concurrent starts. If Voice, the integration, or the channel capability is
disabled, managed rooms deny access. An unused call session can expire without
losing the conversation link.

Enforce the same audience in direct URLs, APIs, room search/hashtags, directory
queries, serializers, MessageBus events, invitation suggestions, status text,
participant lists, and chat history. Do not rely on hidden sidebar entries.
Private room names and DM participants must not leak into global Voice UI or
user statuses. Reuse native private-room status wording where appropriate.

Enabled workspace channels expose Join room on their existing header or sidebar
row even when empty, and current participants only to the eligible audience.
The DM header exposes Start/Join call and the DM list may show an active-call
indicator. Managed calls should not clutter the standalone global room directory.
The existing global Watercooler is a separate site room with its explicit policy.

## Verified upstream behavior

Inspected sandbox core revision:
`9cccc5837dc83a7af376dd40d4cb709cd25b0228`.

- `plugins/voice/lib/voice/guardian_extension.rb`: site-wide group gate followed
  by public/direct-membership/creator/moderator checks; native staff override.
- `plugins/voice/app/models/voice/room.rb`: optional chat-channel link exists,
  but room membership and authorization do not inherit that channel.
- `plugins/voice/app/controllers/voice/calls_controller.rb`: accepts one callee
  username and creates a temporary private room; caller and callee are peers
  who may invite others. It does not bind the room to an existing DM.
- `plugins/voice/app/services/voice/room_inviter.rb`: private invitations create
  Voice membership before checking join eligibility.
- `plugins/voice/app/controllers/voice/room_memberships_controller.rb`: deleting
  membership changes an active role but does not itself disconnect the user.
- `plugins/voice/app/services/voice/chat_session.rb`: linking chat enables
  thread-based call messages, including DM-aware chat checks; it is not a
  shared membership model.
- `plugins/voice/app/services/voice/directory_broadcaster.rb`: private events use
  direct room members, public events use site-wide allowed groups.

Upstream describes automatic Voice/chat association as roadmap work:
https://meta.discourse.org/t/voice-discord-style-voice-and-video-rooms-now-bundled-with-discourse/411337/58

## Acceptance and rollout

Use a separate local core checkout containing Voice. The current local core
predates Voice and has unrelated edits; preserve it and its dirty plugin copy.
Test against the deployed sandbox revision before considering upstream upgrades.

Required cases include channel Voice enable/disable during a call; topics-only
channels; Town Square membership differing from workspace membership; TL1 members
versus TL2 outsiders; public/private channels;
channel guests; owners in unjoined private channels; private DM access by
nonparticipant staff; one-to-one and group DM calls; communication preferences;
concurrent starts; adding/removing DM participants; former creators/owners;
active-call removal and suspension; stale URLs; archive/delete/unarchive;
metadata broadcasts; and integration disablement/rollback. Native room APIs must
not bypass the inherited restrictions. Test real browser state, not only HTTP.

After local request/service/browser checks, publish and deploy only the required
plugin changes to sandbox, verify exact revisions, run the standard canary and
disposable permission probes, and conduct a two-person call across networks.
Production promotion is a separate authorized operation.

Rollback must disable and end managed calls before unloading the integration.
Do not leave stale native memberships or creator privileges usable after plugin
removal. Preserve association data for a controlled recovery.
