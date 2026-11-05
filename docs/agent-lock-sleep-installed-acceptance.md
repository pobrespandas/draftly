# Installed lock, sleep and resume acceptance

Date: 5 November 2026. Installed source: `757dbdb`, with QA compilation enabled.
The app and embedded helper have Developer ID signatures from team `NM92LU2KKV`.
This is isolated QA evidence, not release or notarization acceptance.

## Scope and method

The user approved a read-only connection for one custom theme, `Folder day café 🐼`.
Only `appearance.read` was enabled. Draft, editor, file, Action, native-effect and
management permissions stayed off. Full-library access and renewal stayed off.
The deadline was 04:33 UTC. A real installed MCP helper stayed open. A bounded
monitor called `draftly_themes_get` about every two seconds and logged success or
error without content. The theme was not changed. No model provider was used.

## Observed sequence

| UTC | Evidence |
| --- | --- |
| 04:19:43–04:19:52 | The MCP process read the authorized theme. |
| 04:19:54 | After Control-Command-Q, reads returned `unavailable`. |
| 04:20:05 | Reads returned `interaction_required` while protection was unavailable. |
| 04:25:33 | The user had confirmed seeing the lock screen and unlocking. Native Settings showed access off and the connection paused; reads still failed. |
| 04:25:39–04:26:04 | Only after explicit native enable did the same MCP process read again, within the original deadline. |
| 04:26:06 | The sleep transition cut reads again, before grant expiry. |
| 04:26:10 | The power log recorded Software Sleep. |
| 04:26:13 | The power log recorded DarkWake, then Maintenance Sleep at 04:26:23. |
| 04:36:05 | Another maintenance DarkWake occurred, followed by sleep at 04:36:18. |
| 04:37:30 | The power log recorded a user power-button wake. |
| 04:42:55 | After user-confirmed wake/unlock, native Settings still showed access off. The connection was inactive because its 04:33 deadline had passed. Reads still failed. |

The connection was then revoked through native Settings. A fresh installed CLI
status request returned exit 3 with `permission_denied`. Access remained off. The
monitor ended and a stop marker was written. No active test grant remains.

## Conclusions and remaining checks

This run verifies cut-off on one real user-confirmed lock, no automatic resume on
unlock, explicit resume during the original grant, and cut-off during real sleep.
The first sleep lasted beyond the grant deadline. That run does not prove wake
with a valid grant or explicit resume after wake. The short repeat below supplies
that evidence. The expired grant was not extended or reactivated.

These observations do not establish every lock, Fast User Switching, remote
session, initial locked startup, or delayed-event boundary. Protected-data
availability is not a complete graphical-unlock contract. Normal release startup,
post-update clients and signed distribution remain separate acceptance gates.

Private evidence for the first run is in the `/tmp/draftly-transitions-*`
directory. It includes `monitor.jsonl`, the
transition summary, markers, the power log extract and the final denial. The
monitor source is `/tmp/draftly-lock-sleep-plan/monitor.py`. Credentials stayed in
Keychain and were not included in commands or reports.

## Short sleep repeat with a valid grant

The user approved a new grant with the same one-theme `appearance.read` scope.
Renewal stayed off. The deadline was 05:01 UTC. The same signed QA and installed
helper were used. No write, model call or normal-library access occurred.

| UTC | Evidence |
| --- | --- |
| 04:47:00 | The installed MCP process read the theme. |
| 04:47:16 | Reads stopped on the sleep request. |
| 04:47:21 | The power log recorded Software Sleep. |
| 04:47:23 | The power log recorded DarkWake. |
| 04:47:31 | The power log recorded FullWake from HID activity. |
| After FullWake | The user confirmed unlock. Settings showed protected data available, access off and the unexpired grant paused. Reads still failed. |
| 04:48:17 | Only after explicit native enable, the same MCP process read the theme again. The scope and deadline were unchanged. |

Native Settings confirmed revocation and access off. A fresh CLI status request
returned exit 3 and `permission_denied`; discovery was empty. The monitor stopped.
No active test grant remains. The repeat evidence directory is recorded in
`/tmp/draftly-transition-session-path.txt`.

This verifies wake with a valid grant, no automatic access resume and explicit
resume for this installed QA flow. Initial locked startup and broader session
and release conditions remain separate checks.
