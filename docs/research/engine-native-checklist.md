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
| printing | Native Cancel; corrected short document displayed one page; two completed local PDFs contained all neutral text and continued to the success step after fixing an actor-isolation crash | Task cancel, timeout and owner-close cleanup; large-document rendering latency |
| arrangement | Move/Done, Cancel, explicit-text URL and window-bound showArrange with Undo | Task cancel, timeout, stale navigation and owner close while the panel is open |
| htmlPreview | WebKit typed return with Unicode/null; Cancel stops later steps; nested Context responses | Task cancel, timeout, owner close and late Drafts.send after closure |
| file | Save Cancel and successful output with exact bytes | Action-host bookmark access after restart, denied/lost access, task cancel/timeout in panel, no late write |
| message | Injected tests only; no real composer acceptance | Mail and Messages availability, authorized neutral composition, cancel/timeout/owner close and handoff lifetime |
| callback | Success/error/cancel, overlapping expired/fresh replies, production timeout and ignored late reply, response collections | Exact deadline race has controlled-clock evidence only. Remaining API options are separate |
| shell | UI Unicode success; task cancel, owner close and production timeout stopped the parent/child group and removed temporary output; completed writes stayed in Inbox and recovery passed | Shell-specific URL/Intent entry variants; repeat native timeout/owner-close after the Unicode launcher change; the deadline winner was not isolated |
| shortcut | Script/step waited output and no-wait launch; native CLI response order | Host-operation cancellation/timeout and child cleanup. Intent queue timeout does not accept this operation; detached completion is intentionally unobserved |
| eventAPI | No native scripting query/edit/fetch acceptance recorded | Calendar/Reminders queries and persistence, async fetch, authorization outcomes, cancel/timeout and late results |
| event | Calendar creation panel with existing access: task and dialog Cancel, no save | Successful Calendar persistence, Reminders creation, grant/denial, pending-authorization cancel, timeout and late authorization |
| location | Injected tests only for the current async route | Neutral success or actual denied/unavailable result, authorization cancel, timeout, stopped updates and ignored late result |
| speech | Injected silent tests only for the current async route | Neutral synthesis in a manual session, cancel/timeout/owner close, stopped audio and delegate cleanup |
| transcription | Existing grant: task cancel in audio picker and after selecting synthetic silence; no later step, preserved text | Successful recognition on this adapter, permission request/denial, native timeout and late completion |
| appleScript | Unicode success, intentional error, typing cancel, no remaining helper and later successful action; typed responses | Native timeout and authorized Automation permission request/denial/cancel |
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
