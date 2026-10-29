# Remaining native engine acceptance

Reviewed: 22 October 2026. Reference: the archived 19 October 2026 baseline and
Drafts 54.1.1 (943). This checklist defines the remaining native cases behind
the six partial engine records. The API matrix owns compatibility status.
The dated validation records own observed results. A listed result accepts
only that operation, outcome and entry point.

## Current case inventory

The XML-RPC encoder rejects non-finite numeric parameters, including nested
values. Both script execution paths reject them before JSON serialization can
change them to null. Regression tests passed with the XML-RPC transport suites.
Both script paths now encode JavaScript Date values as XML-RPC dates, including
nested dates, and reject invalid dates. A loopback server checks the actual
request. Uint8Array request values now use XML-RPC base64, including nested
values, views and getter results. Ordinary arrays remain arrays. Responses still
return dates and base64 as strings. Date values returned by JavaScript getters
still follow JSON serialization. The archived reference does not define these
mappings. Drafts comparison and binary response types remain open.
Malformed base64 in an XML-RPC response now returns an error instead of a
successful value, including inside arrays. Tests cover invalid padding, empty
data and XML whitespace. Valid base64 remains a string; its script type mapping
is still unverified.
The HTML-to-Markdown converter preserves blank lines and decoded text inside
`pre`/`code` blocks. It selects a fence longer than any backtick run in the
block. The preference suite passed; Drafts comparison remains separate.
Syntax-highlight spans inside code blocks are removed before HTML entities are
decoded. A focused test preserves encoded markup and blank lines.
HTML image conversion retains alt text and recognizes quoted and unquoted src
attributes without confusing data-src with src. The preference suite covers these
cases and ignoreImages. Decoded image labels escape Markdown punctuation, and
destinations escape parentheses and backslashes. Drafts comparison and other
URL edge cases need separate checks.
Inline and reference links now use the href attribute rather than data-href,
including unquoted values and quoted attributes containing `>`. Focused tests
cover both forms. Other HTML grammar and Drafts parity remain open.
Link and image destinations share escaping for spaces, angle brackets,
parentheses and backslashes after HTML entity decoding. Focused tests cover
inline and reference links and an image destination.
Ignoring links and converting or ignoring images also handles `>` inside quoted
attributes, with focused regression coverage.
Ordered HTML lists now retain numbering and start values, and mixed nested
lists retain indentation and unordered markers. Tests cover both nesting
directions. Other list grammar and Drafts comparison remain open.

[Engine acceptance cases](engine-acceptance-cases-2026-10-22.md) assigns case IDs,
entries, outcomes, cleanup and affected contracts to the remaining work. It
separates actionable checks from reference, permission and system blocks.
[Included configuration comparison](included-configuration-comparison-2026-10-22.md)
records the current Drafts Pro block and Draftly-only characterization. No
configuration precedence has been accepted from Drafts by that attempt.

## Controlled speech permission follow-up

[Speech permission and cleanup](speech-permission-lifetime-2026-10-22.md) records
a red/green transcription cancellation-reason regression and new driver tests.
Requested denials, stale authorization across sessions and capture cleanup are
covered without real permissions or audio. The runner case retains completed
text, stops later steps and Archive, and recovers. These checks do not accept
the outstanding native speech/microphone dialogs or recognition timeout.

## Route checklist

`Sources/Draftly/NativeAsyncRoute.swift` defines these 18 route families.
For each new session, record the actual operation, UI/URL/Intent entry, build,
result, cleanup, late-result behavior, and a following successful action.
Use neutral data and a separate manual QA app. Automatic tests stay headless.
Test a completed print through a local PDF; physical printing is not required.
Message sending still requires an authorized recipient and content.

| Route | Recorded native cases | Remaining acceptance |
| --- | --- | --- |
| model | Explicit onDevice and PCC unavailable responses; actual system readiness inspected; injected absolute-deadline and synchronous cancellation guards passed | Real generation, cancellation, timeout and tool/session cleanup are blocked by readiness |
| prompt | Prompt and SelectPrompt accept, keyboard cancel, task cancel and recovery; URL owner-close Prompt | URL Prompt Cancel, production timeout and following Accept with exact Unicode success callback passed on 22 October. SelectPrompt URL production timeout and filtered-selection recovery also passed on 22 October. Remaining action-confirmation variants stay open. Field options have separate API contracts |
| sharing | Text picker Escape; file openIn Escape and cleanup before handoff. Native Notes extension Cancel/Save and retained attachment copy after temporary cleanup passed on 22 October | Notes production timeout after handoff, retained file, following recovery before provider closure and actual late Cancel cleanup/isolation also passed on 22 October. URL task cancel from the loaded source after Notes handoff, retained file, following success and late provider Cancel cleanup/isolation passed on 22 October. Cold headless execution has no cancel command in an unrelated visible window. URL direct source-window close after Notes handoff also passed on 22 October: retained file, one cancel, following recovery and late provider cleanup without another result. Controlled discovery cancellation and expiry guards now pass (22 October); these are not native service checks. Explicit owner binding now passed native URL picker Cancel and missing-owner rejection with an unrelated window open. File cleanup and following shell recovery passed. These checks did not hand off to a service. Other-service outcomes and legacy sharing remain separate |
| printing | Native Cancel; corrected short document displayed one page; two completed local PDFs contained all neutral text and continued to the success step after fixing an actor-isolation crash; task cancel and panel Cancel closed the panel, retained completed writes without tail/Archive, and allowed a following action; unchanged production120s timeout closed the panel, recorded Error and preserved writes without tail/Archive | Owner-close cleanup remains unaccepted. A clean22 October repeat confirmed File Close disabled and Close All leaving both sheet and source window present with zero callbacks. Panel Cancel then returned one cancel and following shell recovery passed. Do not repeat Close All as owner-close evidence without changed behavior. The126925-UTF16-unit document completed as118 A4 PDF pages after fixing URL owner selection on22 October; all numbered lines and sampled page rendering passed. Panel and callback observation bounds are recorded, without a broad drawing-responsiveness claim |
| arrangement | Move/Done, Cancel, explicit-text URL and window-bound showArrange with Undo; native UI task cancel and production timeout close the panel, retain completed text without tail/Archive, and permit a following Done result | File → Close All during the panel passed on 22 October; stale navigation, direct individual-window close and capability-specific URL/Intent variants remain separate |
| htmlPreview | WebKit typed return with Unicode/null; Cancel stops later steps; nested Context responses; current-image task cancel, owner close and production timeout preserve completed writes without tail/Archive; a new preview stays isolated after an old scheduled timer deadline | Actual delivery of an old WebKit message after closure was not observed; direct late-message rejection has separate headless coverage. URL/Intent capability-specific variants remain separate |
| file | Save Cancel, task cancel, production timeout and following recovery with exact35-byte UTF-8; interrupted targets absent after recovery. Functional QA bookmark picker Cancel, Unicode action read/write, missing-file error and reuse after normal process restart passed | Actual URL/bookmark filesystem write-denial and recovery passed on 22 October. URL export File → Close All and exact-byte recovery also passed on 22 October. TCC/sandbox/revoked-scope denial, individual close where enabled, actual late panel callback and remaining capability-specific URL/Intent checks remain open |
| message | Native Mail handoff returned false sent before send; corrected adapter now fails explicitly before composing, with URL error/recovery verified on 22 October. Mail delivery remains partial | A confirmed-delivery Mail adapter and its send/cancel verification remain pending. A separate authorized AppleScript composer experiment sent one message on 22 October. Its Sent record matched subject and recipient, but exact body comparison failed. Outgoing and Sent object IDs differed. This does not accept Mail.send(). Native recipient-free Messages composition also reported sent before sending (22 October). The corrected adapter now explicitly rejects unconfirmed delivery before composition; URL error/recovery passed. Confirmed Messages delivery, cancel/timeout/owner close and handoff lifetime remain partial |
| callback | Success/error/cancel, overlapping expired/fresh replies, production timeout and ignored late reply, response collections | Exact deadline race has controlled-clock evidence only. Remaining API options are separate |
| shell | UI Unicode success; task cancel, owner close and production timeout stopped the parent/child group and removed temporary output; completed writes stayed in Inbox and recovery passed | Current-image URL task cancel, production timeout, direct owner close and following recovery passed on 22 October, including exact parent/child/temp cleanup. Actual Intent.perform with real shell/child now has headless cancel/timeout cleanup and recovery coverage (22 October). System-delivered App Intent shell Stop cancellation, production120s timeout, direct owner close and recovery passed on 22 October with parent/child/private-folder cleanup and matching history. An isolated native deadline-winner race remains unobserved; controlled exit/deadline tests stay separate |
| shortcut | Script/step waited output and no-wait launch; native CLI response order | Native URL task cancellation and the production60s timeout passed with actual /usr/bin/shortcuts PID and input-directory removal, one matching callback, retained writes without tail/Archive and following recovery (22 October). Independent system service-job stop and actual spawned-child cleanup remain unobserved. Injected-executable interruption stays separate. System-delivered Intent variants remain open; detached completion is intentionally unobserved |
| eventAPI | Native Calendar.default URL access-denied/recovery and user-authorized success passed, including normal process restart (22 October). No names, IDs or event contents exported; no records created. Controlled EventKit waits also reject expiry and queued completion after cancellation with token cleanup | Reminders.default App Intent access-denied result and subsequent URL default-list success plus following Intent recoveries passed on22 October. The user later confirmed the prompt and pressing Allow; pending-authorization cancellation and late-grant isolation remain unaccepted. Calendar event queries/persistence, Reminders task queries/persistence, async fetch, remaining authorization outcomes, timeout and late results remain open |
| event | Calendar creation panel with existing access: task and dialog Cancel, no save | Successful Calendar persistence, Reminders creation, grant/denial, pending-authorization cancel, timeout and late authorization |
| location | Injected tests only for the current async route. Same-turn cancellation before queued cleanup now prevents late authorization from starting updates or delivering success; red/green regression recorded on 22 October. Controlled-clock authorization and coordinate boundary tests now also reject expiry before queued timeout | Native URL timeout, task cancel and following recovery passed on 22 October, with retained writes and one final callback each. No grant or authorization dialog was observed. Neutral success or actual denied/unavailable result, pending-authorization variants, directly observed stopped updates and actual late OS result remain open |
| speech | Headless cancellation, notice ordering and owned-helper cleanup tests; native URL task cancel and production120-second timeout with one matching result and recovery. Later native short-phrase completion passed: Reading complete held callback count zero until OK, then one success. Direct source-window close during the completion notice and during confirmed live-helper playback also returned one cancel without tail/Archive; following shell recovery passed (22 October) | Actual Intent.perform has headless helper cancel/timeout cleanup and retained-write/recovery coverage. System-delivered Intent and selected-voice variants, independent audible-output and output-stop confirmation remain separate. The interrupted first playback-close attempt had no final evidence; the completed repeat accepts the case, not that missing result |
| transcription | Existing grant: task cancel in audio picker and after selecting synthetic silence; no later step, preserved text. Controlled-clock red/green tests now reject expired authorization, file selection and recognition before queued timers, preserving phase cleanup and cancellation reasons (22 October) | URL recognition on this adapter passed on 22 October after an actual user-authorized speech grant: synthetic neutral audio, matching callback/editor text and following shell recovery. Denial, pending-authorization cancellation, native recognition timeout, late completion and remaining entry variants stay open |
| appleScript | Unicode success, intentional error, typing cancel, typed responses; current-image task cancel, owner close and production timeout removed exact helpers/temp folders, kept completed text without tail/Archive and allowed a following native action | Authorized Automation permission request/denial/cancel and cleanup while permission is pending |
| dictation | Earlier 19 October positive/cancel checks predate this adapter. Headless red/green regressions now prevent late speech/microphone grants from advancing a cancelled session before queued cleanup. Phase deadlines also reject expired grants, recording updates and Done before queued timers run; timely phases retain separate budgets (22 October) | Current adapter success, user/task cancel, timeout, speech/microphone authorization and capture cleanup |

Theme-file bookmark checks do not accept the action-host file route. Earlier
dictation/transcription results remain evidence for their tested implementation;
they do not accept the newer asynchronous adapter.

Find the source observations in validation.md under Real callback delivery and
scene creation; Real async prompt keyboard acceptance; HTML, file selection,
and composition delivery; Awaited print, sharing, and arrangement; Template
waits, automation arrangement, and print layout; Native task cancellation during
prompts; Native transcription task cancellation; Native EventKit task
cancellation; Native awaited Shortcut responses; Current Apple model readiness
and unavailable responses; Native callback regression after deadline correction;
Context response contracts and native acceptance; and Context callback
collection acceptance. These headings preserve their session dates and limits.

## Permission cases

Track permission outcomes separately from implementation failures. For speech,
microphone, Calendar, Reminders and location, verify pending authorization,
denied/restricted results, cancellation and late authorization responses.
Capture or location updates must not start after cancellation. Event permission
must not cause a late save. Calendar and Reminders have separate grants.

Automation uses an authorized neutral target. Check denial and cancellation or
timeout of the helper while an OS permission request is pending. File access
requires panel cancellation, actual bookmark access after restart, lost access
and no write after cancellation. Visible success/error notifications remain a
separate native check; Context.fail result/history acceptance does not prove
OS notification delivery. Do not change privacy controls without authorization.

## Other partial engine contracts

Shared included configuration still needs comparison in Drafts before changing
precedence. Compare a saved child value against its default, duplicate root/child
keys, conflicting types, static versus template-resolved inclusion, and repeated
sibling inclusion. Current static flattening and dynamic absent-key insertion
use different rules. Both runners need precise assertions after the reference
behavior is known. A unique child-default test does not settle these cases.

Separator import still needs a genuine neutral exported Drafts group container
and exact presentation comparison. The current importer extracts top-level
actions; current mixed-container tests do not establish outer group metadata
parity. Preserve group identity, options, separators, order and unknown fields;
test rollback and backup recovery once the actual format is established.

On 29 October, Drafts 54.1.1 exported the existing neutral empty group through
Manage Action Groups > Share Group > Export as File. The 227-byte
`.draftsActionGroup` file uses a zlib wrapper around JSON. Its SHA-256 is
`c2ff072b77babb9d957ba508c5490f0287fa7fb68c4b3845a3297ae1dc01d56b`.
The neutral export is in `Tests/DraftlyCoreTests/Fixtures/` for future import
tests. It contains group UUID, name, icon, visibility, disposition, timestamps,
and an empty actions array. It does not show separator or populated-group data.
Draftly now imports this empty compressed file with bounded decompression and
wrapper, checksum, and payload validation. It retains the metadata in the group
record and backup. Automated tests cover corrupt data, size limits, conflicts,
rollback and restore. Native QA imported the real file and displayed the empty
group. The observed `action_circle2` group icon appears as concentric circles
in Drafts. Draftly maps it to the `circle.circle` system symbol and retains the
original value. Other group icons and disposition are retained but not applied.
The symbol mapping still needs a side-by-side check in Draftly QA. The observed Mac
visibility bits now filter the list, bar and search surfaces.
Automated tests also check each Mac visibility bit after reopening a disk
library and restoring a backup. These tests do not verify a native app restart
or the precedence between group and action visibility in Drafts.
On 29 October, the official Drafts Directory Basic group installation link
provided a payload with 31 entries and two separators. The payload came from
https://actions.getdrafts.com/g/1BG and had SHA-256
`311f80fbf4605b7970a1f2ce3f38dbc8be4a8b2898a4639171a64008078826c3`.
The test fixture wraps that payload in locally generated zlib; it is not an
export from the Drafts app. Its SHA-256 is
`141e7b7c29e0b56e3543f3c5d916b7dbdf1a74230a2e8cd9d4d3e7f3d97e519e`.
Import tests check order, separator identity, group symbol, visibility,
backup and repeated import. Native presentation and an actual populated export
remain unverified.
The same directory payload can be installed through a `draftly://actionGroup`
link. Tests cover the official payload and atomic installation with a neutral
group. Opening the link from another app and native replacement review remain
separate checks. Draftly does not register the original Drafts URL scheme.
The action import screen can also load a Directory group page or a pasted
Drafts group link, retain its group data for review, and use the existing
replacement confirmation before saving. A test uses the official Basic payload
in a simulated page; untrusted hosts and HTTP failures are rejected. The screen
and live network flow still need native verification.
Nested imported step objects now use stable JSON key order. This prevents
new imports from differing only because object keys were serialized in a
different order. Group reimport compares older step metadata by JSON content
and preserves matching installed actions. A changed action remains a conflict.
On 29 October, the Drafts Add Items menu still disabled New Action and New
Separator. This did not produce a populated export or verify its format.

On 29 October, each Mac visibility checkbox was changed separately on the same
neutral empty group and exported by Drafts 54.1.1. With all six Mac and iOS
checkboxes enabled, `visibility` was 2016. Disabling Mac List changed it to
1888 (bit 128); disabling Mac Action Bar changed it to 1760 (bit 256);
disabling Mac Search changed it to 992 (bit 1024). With Mac List disabled,
the action group selector showed no available group. The checkboxes were
restored to their original enabled states. This does not establish the iOS bits,
missing-value defaults, or the precedence between group and action visibility.
The After success menu showed Nothing, Archive, Trash, and Ask; only Nothing's
exported `disposition` value 0 is known. No execution outcome was tested.

Generic native UI, URL and actual App Intent sessions already cover final
success/failure/cancel/timeout, queues, owner close, library exclusion and
same-draft two-window ownership. Keep those results. For the unresolved routes
above, record the entry used and its actual final result. Do not infer a full
route-by-entry cross-product from a generic test, or rerun accepted generic
cases as a substitute for missing capability checks. The strict gate stays open.

Native shell lifetime evidence is recorded in validation.md under Native shell
process lifetime — 21 October 2026. It accepts the UI cases in the shell row,
not the other routes or the entire engine.


## Window scene opening — 21 October 2026

The worker now awaits correlated library scene creation and native tab attachment.
Native sequential Zulu/Excluded targets passed with source text preserved. The
registry, adapter and worker tests are headless. Pending native checks: slow scene
creation, pending origin close, cancellation/timeout during creation, concurrent
opens, restored scene IDs and URL/Intent variants. Legacy synchronous opening is
separate. See validation.md, Correlated native tab opening.

Local scene reference update: LibraryView now stores a draft UUID per scene.
Four headless restore guards pass. This does not accept native restoration.
The keep-windows alternative could not be reliably executed by Computer Use;
ordinary Quit observations remain separate. No OS reopening preference changed.
