# Installed agent session lifecycle acceptance

Updated: 4 November 2026. Source: `e0e1be9` on PR #105.

## Setup

The installed Developer ID QA contains the signed helper. It uses a temporary
library with iCloud off. The normal library was not opened. The QA uses the
shared startup path and the live session admission check. It does not inject
an unlocked state. Both the native build and 54 focused application-host and
local-host tests passed.

The user approved a new CLI/MCP connection with only `drafts.read` for draft
`B73F7B46-1AE6-4000-A313-0B0CCB914039`. No editor, other draft, revision, or
Action was selected. Renewal is off. The fixed expiry is 05:34 UTC on
4 November. No credential is in client configuration or this report.

## Observations

- Initial startup showed local access off. No connection was active.
- The approved MCP process read the neutral draft before screen lock.
- At 05:20:40 UTC, the MCP read succeeded. The native lock shortcut was then
  sent. Reads failed from 05:20:44. Discovery returned an empty list at
  05:20:59. Settings showed access off and the connection paused.
- Failed reads continued after the lock request. They did not return draft
  content. Explicit resume restored the same process's read at 05:21:28.
  The scope and fixed expiry did not change.
- A software sleep request ran at 05:22:02. Reads failed from 05:22:04.
  The power log records entry into Sleep at 05:22:08, wake at 05:22:09,
  and display restoration at 05:22:09. Hardware sleep lasted one second.
  This is not prolonged sleep acceptance.
- Settings remained off after wake. An explicit enable attempt was denied
  while the session admission condition was unavailable.
- The exact QA process was terminated and reopened. Startup remained off.
  Enabling access was still denied. This checks an unavailable initial
  session; it does not establish all graphical lock conditions.

## Chat cancellation

A new conversation sent a neutral number-list prompt to GPT-6.1-Sol without
local tools. The UI showed a partial response and an active Stop response
control. Stop removed the busy state and partial response. The prompt remained.
After restart, the saved conversation contained only the user prompt and no
assistant message. A new response after cancellation still needs acceptance.
This observation proves UI cancellation; it does not prove when remote
inference stopped.

## Limits and continuation

The grant was revoked without extending its expiry. The QA was closed. Helper
discovery returned no endpoints. Shared preferences were restored exactly from
the fresh session backup. Only the window frame and selected Settings tab had
changed. No new access remains enabled.

Normal startup with a helper is implemented. This installed app still uses a
QA library. Public console properties and protected-data availability do not
guarantee graphical unlock. See [Apple's clarification](https://developer.apple.com/forums/thread/850327).
Test other lock paths, user switching, longer sleep, and normal distribution
before claiming broad acceptance. Named-client sessions, provider renewal,
Apple Intelligence Cloud tools, and signed update acceptance remain open.

## Client handshake correction

Codex CLI 0.166.0 sent an experimental object that Swift MCP SDK 0.12.1 could
not decode. Source `33e91f9` ignores unnegotiated experimental client capability
objects before SDK dispatch. It does not change tool arguments or permissions.
All 20 MCP boundary and host tests passed. The signed installed helper accepted
the actual captured Codex initialize request and negotiated `2025-06-18`.
This proves the initialization fix. It does not prove a full named-client
session. Codex and Claude Code exposed no tools in the earlier paused-host
probes. Their successful read sessions remain pending.
