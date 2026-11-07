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

## Pagination compatibility with a neutral fixture

On 6 November 2026, Codex CLI 0.166.0 and Claude Code 2.1.318 each
requested all three MCP pages. The fixture used the 137 required tool names.
It returned 50, 50, and 37 names. Both clients called a tool from the last page
and returned its neutral marker.

Codex discovered the tool with no annotations, then blocked the call under
its never-approve policy. The call succeeded when the fixture identified the
tool as read-only. The fixture performed only a read, regardless of the tool
name. This check did not change a Draftly workspace.

The client check used an isolated stdio fixture. It verifies pagination in
both clients. Draftly's Swift bridge tests exercise its actual schemas and
cursor validation separately. These checks do not establish installed
catalog acceptance, deferred tool loading, or comparative token cost.

Claude Code also passed with tool search enabled and the fixture server set
to defer all its tools. The client requested all three pages. Its first tool
call was `ToolSearch`. It then called the fixture tool from page three and
returned the marker. With tool search disabled, it called the same fixture
tool directly and returned the same marker. This establishes both discovery
paths on the fixture. The single runs used different prompt caches, so they
do not establish a token or latency advantage.

## Catalog QA signed update

On 6 November 2026, the signed loopback feed offered QA build 30
(dc88e59) to build 13 (757dbdb plus the earlier QA-only loopback updater
patch). Both app bundles and their helpers passed notarization. Both used
the same isolated library. Sparkle downloaded the signed archive, installed
it in place and relaunched Draftly from the original app path.

The updated bundle reported build 30 and source dc88e59. Strict signature
verification and the stapled ticket passed after installation. The draft
created in build 13 remained in the library and its complete Unicode text
opened in the editor. The Agents pane showed local access off, no approved
connections and protected data available.

### Post-update client and operation checks

After the update, the signed helper returned all 137 available operations
with input and result schemas through the CLI. MCP listed the same 137
tool names without duplicates. Codex CLI 0.166.0 and Claude Code 2.1.318
each called `server.status` on the installed app and received version
0.1.10. Claude Code found the tool through `ToolSearch`.

Both transports rejected an unrelated retry key for
`operations.answerPrompt`, then accepted a valid answer and saved its
marker once. MCP also rejected a duplicate answer. Both transports passed
model mode enumeration, local HTML preview, loopback XML-RPC success and
fault, and OCR of a selected PNG. They also created and read a UTF-8 file
in an approved test folder. Repeating the write request recovered its
result. Forgetting the bookmark left the file in place.

Mail and Messages each opened a composer with neutral text and no
recipient through both transports. The test text was discarded or cleared.
No message was sent. The connection was revoked and local access
was turned off at the end. Calendar and Reminders passed the VM checks below.

## EventKit VM acceptance

On 7 November 2026, signed QA build 40 passed Calendar and Reminders
creation through CLI and MCP in the `Draftly EventKit QA` VM. The app
used the native adapter from 970a352 and the unchanged signed catalog
helper. Apple accepted the combined bundle in notarization submission
`3e482cb7-5760-4a43-b071-97d72e70f26e`. The stapled ticket and strict
signature check passed. Launch Services started the installed app.
The final checks did not use permissions inherited from Terminal.

The app started with local access off. One approved connection had only
native-operation permission. It had no draft, editor, file or library
scope. MCP listed 28 unique tools for that permission. The Calendar
destination was an exclusive local QA calendar. The Reminders destination
was an exclusive QA list in the user's iCloud account, approved for this
check. The checks did not read or change other list contents.

The VM reset only the QA app's Calendar and Reminders OS permissions
before the final launch. Both CLI checks passed on their first request
after the person granted OS access. Both MCP checks then passed in the
same app process.

| Transport | Operation | Verified result identifier |
| --- | --- | --- |
| CLI | `native.calendar` | `E122E7F3-CDA7-4B58-A553-5145AD388C04:E18FCB03-C263-4C14-82E1-F18EA16500FD` |
| CLI | `native.reminders` | `351F576D-C398-4A59-9EE2-D14420D00A82` |
| MCP | `native.calendar` | `E122E7F3-CDA7-4B58-A553-5145AD388C04:6A03377C-55F0-4882-A81D-0C3268802C0B` |
| MCP | `native.reminders` | `5F9E2667-96C4-4B63-9840-0614F851543A` |

Each request used neutral text with `café 🐼`. Calendar requests had no
guests or alarms. Reminders had no due date or alarms. Each check repeated
the same request ID and parameters twice and recovered the same result.
An independent EventKit reader checked the returned identifier, exact
title, exact destination and a single matching item. It then removed only
that test item and checked that no match remained.

The VM checks found two release defects. The hardened app needed the
Calendar entitlement. The signing verifier now rejects a release app
that declares Calendar or Reminders access without that entitlement.
The first Calendar grant also returned `allowed=true` while the class
status was still `notDetermined`. The adapter now resets cached state,
waits for full authorization and waits for the selected destination to
load. Both waits are bounded and cancelable. Neither wait repeats a
write. Denied, restricted and write-only access still fail.

The focused EventKit suite passed 21 tests. The signing suite passed
17 tests. Earlier failing QA requests reported no completed effects.
After the final checks, the connection was revoked. CLI returned
`permission_denied`. MCP returned `-32000` with `permission_denied`.
The Agents pane showed `Revoked` and local access off. The temporary
host-to-VM transfer server was stopped.
