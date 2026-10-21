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
| prompt | Prompt and SelectPrompt accept, keyboard cancel, task cancel and recovery; URL owner-close Prompt | Native timeout; remaining action-confirmation variants. Field options have separate API contracts |
| sharing | Text picker Escape; file openIn Escape and cleanup before handoff | Completed service, file lifetime after handoff, task cancel, timeout and owner close; legacy sharing is separate |
| printing | Native Cancel; corrected short document displayed one page; two completed local PDFs contained all neutral text and continued to the success step after fixing an actor-isolation crash; task cancel and panel Cancel closed the panel, retained completed writes without tail/Archive, and allowed a following action; unchanged production120s timeout closed the panel, recorded Error and preserved writes without tail/Archive | Owner-close cleanup; large-document rendering latency |
| arrangement | Move/Done, Cancel, explicit-text URL and window-bound showArrange with Undo; native UI task cancel and production timeout close the panel, retain completed text without tail/Archive, and permit a following Done result | Stale navigation and owner close while the panel is open; capability-specific URL/Intent variants remain separate |
| htmlPreview | WebKit typed return with Unicode/null; Cancel stops later steps; nested Context responses; current-image task cancel, owner close and production timeout preserve completed writes without tail/Archive; a new preview stays isolated after an old scheduled timer deadline | Actual delivery of an old WebKit message after closure was not observed; direct late-message rejection has separate headless coverage. URL/Intent capability-specific variants remain separate |
| file | Save Cancel, task cancel, production timeout and following recovery with exact35-byte UTF-8; interrupted targets absent after recovery | Action-host bookmark access after restart, denied/lost access, owner close, actual late panel callback and capability-specific URL/Intent checks |
| message | Injected tests only; no real composer acceptance | Mail and Messages availability, authorized neutral composition, cancel/timeout/owner close and handoff lifetime |
| callback | Success/error/cancel, overlapping expired/fresh replies, production timeout and ignored late reply, response collections | Exact deadline race has controlled-clock evidence only. Remaining API options are separate |
| shell | UI Unicode success; task cancel, owner close and production timeout stopped the parent/child group and removed temporary output; completed writes stayed in Inbox and recovery passed | Shell-specific URL/Intent entry variants; repeat native timeout/owner-close after the Unicode launcher change; the deadline winner was not isolated |
| shortcut | Script/step waited output and no-wait launch; native CLI response order | Host-operation cancellation/timeout and child cleanup. Intent queue timeout does not accept this operation; detached completion is intentionally unobserved |
| eventAPI | No native scripting query/edit/fetch acceptance recorded | Calendar/Reminders queries and persistence, async fetch, authorization outcomes, cancel/timeout and late results |
| event | Calendar creation panel with existing access: task and dialog Cancel, no save | Successful Calendar persistence, Reminders creation, grant/denial, pending-authorization cancel, timeout and late authorization |
| location | Injected tests only for the current async route | Neutral success or actual denied/unavailable result, authorization cancel, timeout, stopped updates and ignored late result |
| speech | Injected silent tests only for the current async route | Neutral synthesis in a manual session, cancel/timeout/owner close, stopped audio and delegate cleanup |
| transcription | Existing grant: task cancel in audio picker and after selecting synthetic silence; no later step, preserved text | Successful recognition on this adapter, permission request/denial, native timeout and late completion |
| appleScript | Unicode success, intentional error, typing cancel, typed responses; current-image task cancel, owner close and production timeout removed exact helpers/temp folders, kept completed text without tail/Archive and allowed a following native action | Authorized Automation permission request/denial/cancel and cleanup while permission is pending |
| dictation | Earlier 19 October positive/cancel checks predate this adapter | Current adapter success, user/task cancel, timeout, speech/microphone authorization and capture cleanup |

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
