# Reviewed HTTPS inputs

The command service connects HTTPS sources for `themes.install`, `themes.replace`,
`backups.validate` and `backups.previewRestore`. Coverage stays at 115 connected or
conditional names of 137. These paths require `native.use` and an app-owned
approval before each new download. The app checks resource authority and version
intent before approval and before download.

The private HTTP session uses GET and follows redirects only on the same origin.
It does not use shared credentials, cookies or cache. Theme input is limited to
1 MiB. Backup input is limited to 32 MiB. Backup validation and preview do not
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
