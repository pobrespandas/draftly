# Remaining native engine acceptance

Reviewed: 21 October 2026. Reference: the archived 19 October 2026 baseline and
Drafts 54.1.1 (943). This checklist defines the remaining native cases behind
the six partial engine records. The API matrix owns compatibility status.
The dated validation records own observed results. A listed result accepts
only that operation, outcome and entry point.

## Route checklist

`Sources/Draftly/NativeAsyncRoute.swift` defines these 18 route families.
For each new session, record the actual operation, UI/URL/Intent entry, build,
result, cleanup, late-result behavior, and a following successful action.
Use neutral data and a separate manual QA app. Automatic tests stay headless.
Test a completed print through a local PDF; physical printing is not required.
Message sending still requires an authorized recipient and content.

| Route | Recorded native cases | Remaining acceptance |
| --- | --- | --- |
| model | Explicit onDevice and PCC unavailable responses; actual system readiness inspected | Real generation, cancellation, timeout and tool/session cleanup are blocked by readiness |
| prompt | Prompt and SelectPrompt accept, keyboard cancel, task cancel and recovery; URL owner-close Prompt | URL Prompt Cancel, production timeout and following Accept with exact Unicode success callback passed on 22 October. SelectPrompt URL production timeout and filtered-selection recovery also passed on 22 October. Remaining action-confirmation variants stay open. Field options have separate API contracts |
| sharing | Text picker Escape; file openIn Escape and cleanup before handoff. Native Notes extension Cancel/Save and retained attachment copy after temporary cleanup passed on 22 October | Notes production timeout after handoff, retained file, following recovery before provider closure and actual late Cancel cleanup/isolation also passed on 22 October. URL task cancel from the loaded source after Notes handoff, retained file, following success and late provider Cancel cleanup/isolation passed on 22 October. Cold headless execution has no cancel command in an unrelated visible window. URL direct source-window close after Notes handoff also passed on 22 October: retained file, one cancel, following recovery and late provider cleanup without another result. Other-service outcomes and legacy sharing remain separate |
| printing | Native Cancel; corrected short document displayed one page; two completed local PDFs contained all neutral text and continued to the success step after fixing an actor-isolation crash; task cancel and panel Cancel closed the panel, retained completed writes without tail/Archive, and allowed a following action; unchanged production120s timeout closed the panel, recorded Error and preserved writes without tail/Archive | Owner-close cleanup; large-document rendering latency |
| arrangement | Move/Done, Cancel, explicit-text URL and window-bound showArrange with Undo; native UI task cancel and production timeout close the panel, retain completed text without tail/Archive, and permit a following Done result | File → Close All during the panel passed on 22 October; stale navigation, direct individual-window close and capability-specific URL/Intent variants remain separate |
| htmlPreview | WebKit typed return with Unicode/null; Cancel stops later steps; nested Context responses; current-image task cancel, owner close and production timeout preserve completed writes without tail/Archive; a new preview stays isolated after an old scheduled timer deadline | Actual delivery of an old WebKit message after closure was not observed; direct late-message rejection has separate headless coverage. URL/Intent capability-specific variants remain separate |
| file | Save Cancel, task cancel, production timeout and following recovery with exact35-byte UTF-8; interrupted targets absent after recovery. Functional QA bookmark picker Cancel, Unicode action read/write, missing-file error and reuse after normal process restart passed | Actual URL/bookmark filesystem write-denial and recovery passed on 22 October. URL export File → Close All and exact-byte recovery also passed on 22 October. TCC/sandbox/revoked-scope denial, individual close where enabled, actual late panel callback and remaining capability-specific URL/Intent checks remain open |
| message | Native Mail handoff returned false sent before send; corrected adapter now fails explicitly before composing, with URL error/recovery verified on 22 October. Mail delivery remains partial | A confirmed-delivery Mail adapter and its send/cancel verification remain pending. A separate authorized AppleScript composer experiment sent one message on 22 October. Its Sent record matched subject and recipient, but exact body comparison failed. Outgoing and Sent object IDs differed. This does not accept Mail.send(). Native recipient-free Messages composition also reported sent before sending (22 October). The corrected adapter now explicitly rejects unconfirmed delivery before composition; URL error/recovery passed. Confirmed Messages delivery, cancel/timeout/owner close and handoff lifetime remain partial |
| callback | Success/error/cancel, overlapping expired/fresh replies, production timeout and ignored late reply, response collections | Exact deadline race has controlled-clock evidence only. Remaining API options are separate |
| shell | UI Unicode success; task cancel, owner close and production timeout stopped the parent/child group and removed temporary output; completed writes stayed in Inbox and recovery passed | Current-image URL task cancel, production timeout, direct owner close and following recovery passed on 22 October, including exact parent/child/temp cleanup. Actual Intent.perform with real shell/child now has headless cancel/timeout cleanup and recovery coverage (22 October). System-delivered shell App Intent variants and an isolated deadline-winner race remain open |
| shortcut | Script/step waited output and no-wait launch; native CLI response order | Actual Shortcuts-service cancellation/timeout and child cleanup. Injected-executable waited cancellation/timeout now have process and input-removal evidence (22 October). Intent queue timeout does not accept this operation; detached completion is intentionally unobserved |
| eventAPI | Native Calendar.default URL access-denied/recovery and user-authorized success passed, including normal process restart (22 October). No names, IDs or event contents exported; no records created. Controlled EventKit waits also reject expiry and queued completion after cancellation with token cleanup | Calendar event queries/persistence, Reminders queries/persistence, async fetch, remaining authorization outcomes, cancel/timeout and late results |
| event | Calendar creation panel with existing access: task and dialog Cancel, no save | Successful Calendar persistence, Reminders creation, grant/denial, pending-authorization cancel, timeout and late authorization |
| location | Injected tests only for the current async route. Same-turn cancellation before queued cleanup now prevents late authorization from starting updates or delivering success; red/green regression recorded on 22 October. Controlled-clock authorization and coordinate boundary tests now also reject expiry before queued timeout | Native URL timeout, task cancel and following recovery passed on 22 October, with retained writes and one final callback each. No grant or authorization dialog was observed. Neutral success or actual denied/unavailable result, pending-authorization variants, directly observed stopped updates and actual late OS result remain open |
| speech | Headless cancellation, notice ordering and owned-helper cleanup tests; native URL task cancel and production120-second timeout with one matching result and recovery. Later native short-phrase completion passed: Reading complete held callback count zero until OK, then one success. Direct source-window close during the completion notice and during confirmed live-helper playback also returned one cancel without tail/Archive; following shell recovery passed (22 October) | Actual Intent.perform has headless helper cancel/timeout cleanup and retained-write/recovery coverage. System-delivered Intent and selected-voice variants, independent audible-output and output-stop confirmation remain separate. The interrupted first playback-close attempt had no final evidence; the completed repeat accepts the case, not that missing result |
| transcription | Existing grant: task cancel in audio picker and after selecting synthetic silence; no later step, preserved text. Controlled-clock red/green tests now reject expired authorization, file selection and recognition before queued timers, preserving phase cleanup and cancellation reasons (22 October) | Successful recognition on this adapter, permission request/denial, native timeout and late completion |
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
