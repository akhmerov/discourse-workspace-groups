# Voice for research workspaces: product analysis

Status: product recommendation for discussion, 2026-09-22. This document does
not authorize implementation or deployment. Native TL2 direct calls are already
enabled in production and sandbox; workspace integration remains to be built.

VSF should support three related activities: calling particular people, talking
in a project's context, and making oneself available in a shared place. The
recommended product combines DM calls, calls in workspace channels, and a small
number of persistent workspace rooms. Existing groups define the regular
audience. A meeting is a session in one of these places, with an explicit start,
end, and, where permitted, temporary guests.

This revises the earlier proposal in two substantive ways. A workspace room can
exist without a chat channel. A visitor can be admitted to a session without
receiving permanent channel membership or access to its history. These are
product recommendations, not capabilities already supplied by our integration.
The earlier [technical proposal](voice-integration.md) needs reconciliation
before implementation, particularly its chat-only binding and invitation rules.

**What the evidence establishes.** Discourse's native product emphasizes
persistent rooms, visible participants, and staying connected while browsing;
it also supplies profile-based direct calls. The Discourse team reports using
it for its own meetings, while describing the feature as early and recommending
small-group testing. This establishes functionality and a use case, not proven
reliability for VSF research meetings. [Discourse announcement](https://meta.discourse.org/t/voice-discord-style-voice-and-video-rooms-now-bundled-with-discourse/411337)

Two established interaction models are useful references. Discord has persistent
voice channels that people enter. Slack starts huddles from channels and DMs,
keeping a call near the conversation that prompted it. Slack also distinguishes
permission to attend a huddle from access to its channel history. VSF benefits
from both models, with its own explicit permission rules.
[Discord voice channels](https://support.discord.com/hc/en-us/articles/19583625604887-Voice-Channels-FAQs),
[Slack huddles](https://slack.com/intl/en-gb/help/articles/4402059015315-Use-huddles-in-Slack)

Current VSF channel metadata includes general discussion, group meetings, and
writing contexts. The workspace plugin supports chat-only, topics-only, and
combined channels. These observations establish useful places for calls; they
do not measure demand. No private message contents or Voice attendance records
were used for this analysis. The research-group scenarios below are hypotheses
to test with members, not claims about their observed behavior.

**Likely uses and their different requirements.**

| Situation | Likely audience | Natural entry point | What makes it useful |
| --- | --- | --- | --- |
| Ask a colleague about a calculation or result | Two people | Existing DM or user card | A quick invitation, immediate screen sharing, little setup |
| Debug code, inspect data, or revise a figure together | Small project team | Project channel | The relevant links and discussion are already there; others in the project can join |
| Supervisor meeting or sensitive discussion | Explicitly chosen people | One-to-one or group DM | Predictable audience and no workspace-wide presence announcement |
| Coffee, open office hours, or quiet writing together | Whoever chooses to drop in | Persistent workspace room | A known place, visible occupants, and a clear invitation to join |
| Recurring group meeting or journal club | A known group, sometimes with a visitor | Meeting channel or event with a stable room link | Predictable location, agenda, readable shared material, and clear guest access |
| Consult a collaborator from another institution | Selected members plus a visitor | Group DM or a room session with an admitted guest | Joining the meeting does not expose unrelated discussions |
| Seminar, large group meeting, or hybrid room | Larger audience and possibly anonymous visitors | Event and meeting service | Capacity, admission, accessibility, and room audio requirements exceed the currently validated setup |

The strongest initial value hypothesis is small project collaboration: someone
already discussing a plot can move into speech and share it without creating a
meeting elsewhere. Direct calls serve deliberate contact. The distinctive value
of a common room is discovery: a person may join because someone is there,
without having planned to call that person.

That last use needs a social convention. A room labelled Coffee means visitors
are welcome; a quiet-writing room can mean microphones are usually muted. An
empty room alone does not create a habit. A predictable, voluntary coffee or
writing time is a reasonable way for a group to try it. Co-located groups may
find project calls more useful; distributed groups may value a common room more.
Time-zone overlap limits the latter. These are product hypotheses.

Research on remote information work found fewer connections across groups and
more siloed collaboration after a move to remote work. It supports examining
informal contact as a need, but does not show that adding a voice room solves it,
nor directly establish the behavior of academic groups.
[Yang et al., Nature Human Behaviour](https://doi.org/10.1038/s41562-021-01196-4)

**One coherent room model.** A persistent place has a name, purpose, stable link,
and regular audience. Individual sessions come and go. Three entry points expose
that model without making users administer a second organization:

1. A workspace owner can enable a common room, pinned in that workspace even
   when empty. Its regular audience is the workspace group. Start with one;
   owners can add another when concurrent uses need different social conventions,
   such as coffee and quiet work. A smaller permanent audience belongs in a
   private channel. A common room does not require joining a particular general
   chat, and remains useful to a workspace organized around topics.
2. Every eligible workspace channel can expose Start call / Join call. Its
   regular audience is the channel group, including that channel's guests.
   Provision the native room when needed. Show activity beside the channel;
   avoid a second directory containing an empty room for every channel. Topics-only
   channels use the same access model without silently enabling chat. Managers
   can disable calls in channels such as announcements.
3. One-to-one and group DMs expose the same call controls, using the conversation's
   participants. A call from a user card remains a convenient direct entry point.
   The UI must distinguish a call tied to an existing DM from a temporary call
   with selected people; it must not claim to share a history it does not use.

One active session per channel keeps simultaneous starts together. A separate
side discussion can use a group DM. Two unrelated meetings should not fight for
the workspace common room: use their project or meeting channels. No participant
should be silently moved, evicted, or connected to audio when following a link.

A channel or room link can be placed in an existing meeting event or calendar
invitation. It locates the meeting; it does not grant access, reserve capacity,
or promise that the room will be empty. Creating a new booking/calendar product
is unnecessary for this integration. Temporary guest invitations, however, must
identify a particular session rather than grant access to every later meeting.

**Make the audience understandable before joining.** The room view should state
who can join: all workspace members, members of a named channel, or the people
in a DM. Show current participants separately; three people present does not
mean only those three are allowed to enter. Visiting guests must also be visible.
A pre-join view should expose microphone and camera state. Opening a workspace,
channel, DM, or invitation must never itself transmit audio or video.

| Place | Regular access | Who starts or joins | Management |
| --- | --- | --- | --- |
| Workspace common room | Current workspace group | Eligible workspace members | Workspace owners |
| Workspace channel call | Current channel group | Eligible channel members | Current channel managers |
| Private channel call | Current private-channel group | Eligible private-channel members | Managers of that private channel |
| DM call | Current DM participants | Eligible participants, subject to communication preferences | Peers and the DM's existing membership rules |
| Guest visit to a room session | Explicit, temporary admission | Invited authenticated user | Manager of that room's scope |

Trust level and group membership answer different questions. TL2 remains the
current production direct-call policy. For the proposed workspace integration,
actual group membership should establish the room audience, subject to site-wide
account restrictions and a Voice kill switch. A legitimate TL1 member should not
need a promotion solely to attend their group's call. That policy change is a
separate implementation decision; this analysis changes no trust levels.

Workspace owners have no ordinary entitlement to unjoined private channels or
other people's DMs. Creating or starting a call does not confer lasting ownership.
Removing a member must remove their eligibility and active participation in the
supported client. Private room names, participants, and activity must be hidden
from people outside the permitted audience. Any administrative recovery path
must be explicit and separate from normal room participation.

**Visitors need session access, not accidental access to research history.**
For a lasting collaboration, add the collaborator to the appropriate channel.
For a one-off consultation, either create a group DM with the intended people
or admit the visitor to a particular room session. These operations have
different consequences and need different labels in the UI.

The recommended guest policy is conservative and explicit: room managers admit
authenticated VSF users for one session; ordinary members can request an
invitation. Private-room guest admission can be disabled. A guest sees the room
purpose and present participants, but receives no channel membership, earlier
messages, workspace directory access, or permission to invite others. A copied
link alone never admits another account. Guests cannot keep a meeting open after
all regular members leave, and access ends when the session ends.

Every participant must be able to see that a guest is present. Existing members'
access to a channel is not silently narrowed to the people currently in the
call. If a meeting requires a smaller audience, use a private conversation.
Likewise, adding a third person must not silently expose an existing one-to-one
DM or its history; present an explicit group call with its own audience.

Guest text is a design consequence, not an incidental implementation detail.
An admitted guest needs somewhere to exchange a paper link. Provide clearly
labelled session messages with an explicit retention/access rule, separate from
private channel history. Regular members can deliberately copy useful material
back to the channel. The guest feature is not complete until this text boundary,
expiry, and behavior during member removal are specified and tested together.

Anonymous visitor links would require additional admission and abuse controls.
They are outside the recommended scope of this authenticated workspace product.
For visitors without VSF accounts, account invitation or an external meeting
service remains an explicit choice. Do not advertise universal guest links.

**Keep interruptions and social pressure low.** Starting a channel call changes
its activity indicator; it does not ring the whole workspace. A direct call can
ring its recipient. A group DM offers a targeted invitation to its participants.
All invitations respect communication restrictions and do-not-disturb settings.
A guest invitation notifies only the invited person and the session's occupants.

Presence is useful for finding a conversation, but it should not become an
attendance measure. Being online is not an invitation to call, being in a common
room is not evidence of working, and declining a call needs no explanation.
Keep the approved analytics-off policy. Do not add attendance lists, duration
rankings, automatic recordings, or transcripts as a side effect of integration.
User-authored links and conclusions can remain in the appropriate conversation.
Provide text participation and a clear way to use an accessible alternative;
captions are currently disabled, so accessibility needs cannot be assumed met.

**Research usefulness depends on more than connection success.** Test whether
participants can read equations, plot labels, and editor text during screen
sharing. Check switching between a shared document and the forum, reconnecting,
choosing the right microphone, and joining across university and home networks.
For a hybrid meeting, intelligible room audio and a usable view of the board
matter more than adding another room name. Shared whiteboards and collaborative
documents can remain external links; screen sharing alone is not a whiteboard.

The approved deployment currently caps calls at eight participants and uses
peer-to-peer media. That fits a subset of the scenarios, not an unrestricted
weekly group-meeting promise. Show capacity before people organize a meeting;
a ninth participant must get an understandable explanation. Larger meetings need
a separately validated transport/capacity decision or an external meeting link.
The room, audience, and invitation model should remain the same if transport
changes. Strong server-enforced removal also requires a media architecture that
can enforce it; the earlier technical proposal records the peer-to-peer limit.

**How to evaluate the complete integration.** Product completeness means the
room, DM, privacy, guest, and lifecycle rules agree. Validation can use several
small trials without splitting those requirements into separate products. Use
volunteers for a project discussion, a coffee/writing session, a private meeting,
and a meeting with a visiting collaborator. No trial invitations are sent as
part of this analysis.

Ask whether people could predict the audience before joining; whether moving
from text to voice was easier; whether they could share and read the relevant
material; whether visitors could participate without seeing history; and whether
they would choose it again. Observe failure recovery and unwanted interruptions.
Use participant feedback and deliberately observed test sessions while analytics
remain off. A high number of room-hours is not a useful success criterion.

The most consequential hypotheses to resolve before implementation are whether
groups want an ambient common room, how often they need visitors without accounts,
and whether their intended meetings fit eight people. The permission and room
model above makes those constraints explicit without treating room creation as
a substitute for understanding the group's work.
