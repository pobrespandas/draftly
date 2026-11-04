# Codex and Claude Code installed acceptance

Date: 4 November 2026. Source: `fdc05d2`. Environment: isolated signed QA.
The app and bundled helper used Developer ID team `NM92LU2KKV`.
This report covers one scoped editing flow. It is not release acceptance.

## Grant and isolation

The app started with access off. Admission stayed closed until the user
unlocked the Mac. The native diagnostic then reported console, completed
login and protected data as available. No admission rule was bypassed.
The user approved a CLI/MCP connection for one neutral draft and its current
editor. The grant allowed draft read/write and editor read/write only.
It excluded the other draft and all actions. Renewal was off. The grant
expired at 12:27:26 UTC and was revoked at about 12:18 UTC.

Both clients used the configuration from the installed signed helper.
Credentials stayed in Keychain. Temporary client configuration did not change
global MCP settings. Built-in shell and file tools were disabled. Only the
approved neutral content was sent to the model providers.

## Results

| Check | Codex CLI 0.166.0 | Claude Code 2.1.316 |
| --- | --- | --- |
| Real model and configured MCP connection | Passed | Passed |
| Read approved draft and editor | Passed | Passed |
| Other draft returns `not_found` | Passed | Passed |
| Prepare version-checked editor append | Passed | Passed |
| Execute once with prepared retry key | Passed | Passed |
| Read back exact Unicode line | Passed | Passed |

Codex appended `QA Codex client café 🐼`. Claude appended
`QA Claude client café 🐼`. Each append included one preceding newline.
UTF-16 lengths changed from 106 to 130, then to 155. Native UI confirmed
both lines. The other draft retained its earlier modification time.
Neither client retried a write. A later read can return a different version
after save; this test does not prove every version transition.

The native UI confirmed revocation. A fresh signed CLI status request returned
exit 3 and `permission_denied`. Access was disabled. QA then quit, and the
saved pre-test preferences were restored. The normal library was not opened.

## Limits and retained evidence

Private logs remain in the acceptance work directory identified by
`/tmp/draftly-current-acceptance-session.json`. They include client output,
the generated MCP configuration, the pairing response and the denial after
revocation. Do not commit private logs or credentials.

Normal locked startup, real lock/sleep/resume, all operation families,
provider renewal and cancellation, notarized packaging and post-update client
sessions still require separate acceptance. Later bookmark, transfer and wait
changes were not present in this installed source.
