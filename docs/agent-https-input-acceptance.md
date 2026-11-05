# Reviewed HTTPS inputs

The command service connects HTTPS sources for `themes.install`, `themes.replace`,
`backups.validate` and `backups.previewRestore`. Coverage stays at 115 connected or
conditional names of 137. These paths require `native.use` and an app-owned
approval before each new download. The app checks resource authority and version
intent before approval and before download.

The private HTTP session uses GET and follows redirects only on the same origin.
It does not use shared credentials, cookies or cache. Theme input is limited to
8 MiB (`AgentRequest.maximumBytes`). Backup input is limited to 32 MiB. Backup validation and preview do not
restore the library. Downloaded themes use custom mode.

The parent operation records the download effect. Recovery does not download the
same request again. A changed request with the same identity is rejected. Failure
after download submission returns an uncertain outcome. The journal does not
store the source URL, its query or downloaded content.

## Evidence and limits

Focused tests passed: eight methods in three suites. The HTTPS service tests use
an injected fetch function. They cover approval, denial, cancellation, Stop Work,
read failure, invalid input, authority, stale intent and recovery without replay.
Native Debug and the strict full suite passed: 2,713 tests (1 consumer,
195 contracts, 833 Core and 1,684 application tests). Evidence is in
`/tmp/draftly-https-input-full.log`. The bounded transport has separate loopback
tests.

A temporary test called `AgentHTTPSImport.download` with the public fixture
`theme-development-folder/day.json` at commit `64f3038` on GitHub raw over real
TLS. Download and JSON decoding passed. A 16-byte limit and a missing URL both
failed as expected. Evidence is in `/tmp/draftly-https-live-acceptance.log`. The
temporary network test was removed after the run; CI has no network dependency.

Approval in the signed installed app, lock and sleep behavior,
client acceptance and signed distribution remain open. Agents stay disabled for
publication. These tests do not establish production acceptance.

## Installed QA checkpoint

The isolated installed QA now uses source `757dbdb` with `DRAFTLY_AGENT_QA`.
The native QA build passed. The current helper was packaged with its matching
profile. App and helper static signature checks passed under team `NM92LU2KKV`.
This is not notarization evidence. The normal installed app was not replaced.

Native Settings showed access off, no approved connections and no activity.
Admission reported `console=true`, `login=true`, `protectedData=false`. No grant
was created. Installed download acceptance must wait for protected data to become
available. Do not bypass this check. The recovery directory is recorded in
`/tmp/draftly-https-candidate-path.txt`. It contains the previous QA bundle and
shared preference backup. Close QA before any preference restoration.

The user then confirmed a direct Mac unlock. Changing Settings tabs and fully
restarting QA still reported `protectedData=false`. Access stayed off and no
connection was created. Unlock confirmation alone does not close this gate.
Apple describes this API as protected-data availability, not a complete graphical
screen-lock contract. See [AppKit property documentation](https://developer.apple.com/documentation/appkit/nsapplication/isprotecteddataavailable)
and the [DTS discussion](https://developer.apple.com/forums/thread/850327).
The cause of the persistent unavailable state is not established.

## Admission recheck — 5 November

Two isolated Developer ID AppKit probes reported protected data available at
launch and after one run-loop second. One enabled secure state restoration; the
other disabled it. Both returned true. Draftly then also reported console, login
and protected data available in native Settings. Access remained off and there
were no approved connections. This clears the observed admission condition. It
does not establish why the previous process reported false or prove lock handling.
No protection was disabled and no admission source was replaced.

The retained probe source and outputs are in
`/tmp/draftly-protected-data-probe`. The source input bound above now states the
actual `AgentRequest.maximumBytes` value. The earlier temporary TLS smoke used a
separate explicit 1 MiB limit.

## Installed CLI and MCP acceptance — 5 November

The user approved one temporary connection in the isolated QA. Its grant ended
at 03:24 UTC, had no renewal, and allowed appearance read/manage, approved file
reads, backup validation permissions and native effects. Draft and editor access,
Action execution, file writes, unrestricted scripts and permanent deletion stayed
off. The library had zero drafts. No normal library was opened.

Native approval showed the exact GitHub raw fixture URL, GET, same-origin
redirects and the 8 MiB limit before theme download. The installed helper returned
an accepted operation. After approval, its original request returned the installed
resource. `themes.list` showed exactly one custom theme, `Folder day café 🐼`.

A second request was cancelled while waiting for approval. Cancellation returned
accepted, then the original request returned `cancelled`. The review disappeared.
After full app restart, access was off and the same connection was paused. The
user-authorized session was enabled again within its original deadline. The
first request returned its original result; the second still returned cancelled.
Only one theme remained. No repeated approval appeared. These checks establish
result recovery and no duplicate installation; they do not independently count
outbound network packets. Live version tokens are process-local and can differ
from the original recovered result token after restart.

The installed MCP helper initialized with protocol `2025-06-18`. Real
`tools/call` requests recovered the same installation and listed the single theme.
MCP then submitted HTTPS backup validation. Native review showed the 32 MiB limit
and the purpose “Validate the backup without restoring it”. After approval, the
original request returned `valid=true`, with two themes in the input. The library
still had only its one installed theme. No backup was restored.

Native UI then confirmed the connection revoked and access off. A new installed
CLI status call returned exit 3 with `permission_denied`. Discovery returned an
empty array. No active grant remains. Private request/response evidence is in
the directory recorded by `/tmp/draftly-https-installed-session-path.txt`.
Credentials were not placed in commands, logs or this report.

This closes this scoped installed theme-install, backup-validation, cancellation
and result-recovery flow. Installed theme replacement and backup restore preview,
real lock/sleep transitions, normal release startup, provider acceptance,
notarization and signed updates remain open. The previous admission failure no
longer reproduced; its root cause is not proven. Agents are not ready to publish.
