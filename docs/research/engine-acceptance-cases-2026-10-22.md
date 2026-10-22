# Engine acceptance cases — 22 October 2026

## Scope and state

The strict engine gate has 18 diagnostics for six partial contracts. Each has
three diagnostics: incomplete status, pending native verification and remaining
limitations. These are not 18 independent implementation defects.

This inventory splits actionable work from reference, permission and system
blocks. It supplements engine-native-checklist.md. The API matrix still owns
compatibility status. An accepted generic entry does not accept another native
operation. Do not generate a full route-by-entry cross-product.

Contract keys below: I = shared included scripts; S = separator imports;
W = worker isolation and responsiveness; H = host request lifetime;
C = task cancellation; E = common asynchronous entry points.

States: READY means a controlled test or separate native QA session can proceed.
REFERENCE means the required Drafts comparison is blocked by Pro in this session.
PERMISSION means a real permission outcome needs a user-operated system dialog.
IMPLEMENT means a functional capability is missing. SYSTEM means the last
recorded system readiness prevents the case; recheck readiness before a session.
OBSERVE means a real late event or race has not been observed. A controlled test
must not be presented as that native observation.

Each native case must record operation, entry, outcome, execution identity,
cleanup, retained completed effects, missing later/success effects, exactly one
final report/callback where applicable, and a following successful action.
Late events must not affect the next execution. Keep resource evidence separate
from presentation dismissal. Use neutral QA data. Automatic tests stay headless.

## Reference cases

| ID | Operation and entry | Pending decision or observation | Cleanup and preservation | Contracts | State |
| --- | --- | --- | --- | --- | --- |
| CFG-01 | Include child by UUID, literal name and template; both runners | Child saved value versus its default when root has no key | No configuration write; one root log | I | REFERENCE |
| CFG-02 | Root/child duplicate key; static and template include | Root default versus child default; repeat with root saved value | Preserve both stored actions | I | REFERENCE |
| CFG-03 | Root string versus child number or Boolean | Winning value and JavaScript type | No silent persisted type conversion | I | REFERENCE |
| CFG-04 | Observe before, inside and after inclusion | When the child key becomes visible | Preserve shared context; one result | I | REFERENCE |
| CFG-05 | Two siblings included twice, with runtime edits | First/last default precedence and retention of runtime edits | No configuration persistence or extra child log | I | REFERENCE |
| SEP-01 | Genuine Drafts exported action-group container through import UI | Group identity/options, separators, order and exact presentation | Unknown fields retained; failed import atomic | S | REFERENCE |
| SEP-02 | Imported genuine group through backup and restore | Same group and action relationships after restart/restore | No identity loss or partial restore | S | REFERENCE, depends on SEP-01 |

CFG-01 through CFG-05 have Draftly characterization, not reference acceptance.
See included-configuration-comparison-2026-10-22.md for inputs, outputs and the
manual probe. The authentic exported group is still required; the empty neutral
group created during this attempt is not a format fixture.

## Permission cases

Run these in separate manual sessions. Do not reset privacy databases. Check the
actual permission state first. Existing grants cannot prove pending-authorization
behavior. Record distinct outcomes using the three IDs in each row. No positive
case requires private content.

| IDs | Operation and planned entry | Individual outcomes still needed | Required cleanup | Contracts | State |
| --- | --- | --- | --- | --- | --- |
| CAL-DENY / CAL-CANCEL / CAL-LATE | Calendar creation, UI | Denied/restricted; cancel pending grant; grant after cancellation | No event save or late success | W,H,C,E | PERMISSION |
| REM-DENY / REM-CANCEL / REM-LATE | Reminders query/create, URL | Denied/restricted for creation; cancel pending grant; grant after cancellation | No task save or late query effect | W,H,C,E | PERMISSION |
| LOC-DENY / LOC-CANCEL / LOC-LATE | Location, URL | Actual denied/unavailable; cancel pending authorization; actual late result | No update start after cancellation; observe stopped updates | W,H,C,E | PERMISSION |
| SPEECH-DENY / SPEECH-CANCEL / SPEECH-LATE | Transcription, URL | Denied/restricted; cancel pending grant; recognition delivered after closure | No recognition advance or late text insertion | W,H,C,E | PERMISSION / OBSERVE for late recognition |
| MIC-DENY / MIC-CANCEL / MIC-LATE | Dictation, UI | Denied/restricted; cancel pending grant; late microphone/speech grant | No recording start or retained capture after cancellation | W,H,C,E | PERMISSION |
| AUTO-DENY / AUTO-CANCEL / AUTO-TIMEOUT | AppleScript, URL, neutral authorized target | Denied Automation; cancel pending permission; production timeout while pending | Helper and private temporary files removed | W,H,C,E | PERMISSION |
| FILE-DENY | File/bookmark, URL | Actual revoked scope or TCC/sandbox denial | No write; explicit error and successful later authorized operation | W,H,E | PERMISSION |

Calendar default-query denial and Reminders default-list denial already have
native evidence. The creation rows do not ask to repeat those default queries.
User permission to run a case does not count as an observed permission outcome.

## Resource and result cases

| ID | Operation and entry | Pending outcome | Required resource observation | Contracts | State |
| --- | --- | --- | --- | --- | --- |
| CONFIRM-01 | Action confirmation, UI | Accept then separate Cancel before first step | No step effect on Cancel | W,H,C,E | READY |
| PRINT-01 | Print, UI | Actual individual owner close with pending print operation | Panel/operation cleanup, one cancel; Close All is not evidence | H,C,E | READY; first establish a supported close path |
| ARRANGE-01 | Arrange, URL | Direct owner close and stale navigation | Owned presentation closed; no stale edit | H,C,E | READY |
| HTML-01 | HTML return, URL | Actual old WebKit message after owner closure and a new preview | Old message cannot finish or edit the new request | H,C,E | OBSERVE |
| FILE-01 | Save/export, URL | Actual late panel callback; individual close where enabled | No post-cancel write or second callback | H,C,E | OBSERVE / READY for supported close |
| SHARE-01 | Sharing to a service other than Notes, UI | Actual provider completion and cancellation | Separate handoff lifetime from prepared-file retention and release | W,H,C,E | READY; choose a neutral local provider |
| MESSAGE-01 | Mail and Messages send | Confirmed send result, distinct from composer handoff | Track delivery, cancel, timeout and owner lifetime | H,C,E | IMPLEMENT; no confirmed-delivery adapter |
| CALLBACK-01 | Callback URL, URL entry | Native reply at deadline boundary | One winner; fresh execution unaffected | H,E | OBSERVE; controlled-clock proof already exists |
| SHELL-01 | Shell, URL | Native exit/deadline winner isolated from host deadline | Parent/child and temporary-file cleanup | H,C,E | OBSERVE; controlled boundary proof already exists |
| SHORTCUT-01 | Waited Shortcuts, URL | Independent service-job stop and actual spawned-child cleanup | CLI exit alone is insufficient | H,C,E | READY / OBSERVE |
| SHORTCUT-02 | Waited Shortcuts, system-delivered App Intent | Stop, timeout and following recovery | Input directory and actual external work cleanup | H,C,E | READY |
| EVENT-01 | Calendar event creation, UI | Successful persistence of a neutral event | Verify the created record, then authorized cleanup | H,E | READY with access; fixture cleanup requires authorization |
| EVENT-02 | Reminders creation, UI | Successful persistence of a neutral task | Verify the created record, then authorized cleanup | H,E | READY with access; fixture cleanup requires authorization |
| EVENT-03 | EventKit queries/fetch, URL | Production timeout and actual late fetch result | Tokens removed; no late context result or save | H,C,E | READY / OBSERVE |
| LOC-01 | Location, URL | Neutral successful result or actual unavailable outcome | Independently observe stopped updates | W,H,E | PERMISSION; no private coordinates in evidence |
| VOICE-01 | Speak, system-delivered App Intent | Completion, Stop and timeout with selected voice | Independently confirm audible start/stop and owned helper cleanup | W,H,C,E | READY; separate audible manual session |
| TRANSCRIBE-01 | Transcription, URL | Native recognition timeout on neutral audio | Recognition and file-selection cleanup; text unchanged | W,H,C,E | READY with grant |
| DICTATE-01 | Current dictation adapter, UI | Success and user Cancel | Neutral text and native Undo; microphone released | W,H,E | PERMISSION for first grant; then READY |
| DICTATE-02 | Current dictation adapter, URL | Task cancel and production timeout | No late capture/text, retained prior writes, recovery | W,H,C,E | PERMISSION for first grant; then READY |
| MODEL-01 | On-device model, URL | Real generation, cancel and timeout | Session/tools released; one report | W,H,C,E | SYSTEM; last readiness was unavailable |
| MODEL-02 | PCC model, URL | Real generation, cancel and timeout | Session/tools released; one report | W,H,C,E | SYSTEM; last readiness was unavailable |
| NOTIFY-01 | Action success/error notifications, UI | Actual OS notification delivery | No duplicate or wrong-result notification | E | READY subject to actual notification settings |

MESSAGE-01 needs separate Mail and Messages contract decisions. Do not infer
platform-wide unavailability from the current sharing-service limitation. A
future send test needs a specifically authorized recipient and message.
Do not turn the model block into an exclusion or claim generation cancellation
from an unavailable response.

## Scene and entry obligations

These are distinct from already accepted generic queue, exclusion and same-draft
two-window ownership sessions. Use one actual URL and one system-delivered Intent
where scene dispatch differs. Do not substitute a direct Intent.perform call.

| ID | Operation and entry | Pending outcome | Required cleanup | Contracts | State |
| --- | --- | --- | --- | --- | --- |
| SCENE-01 | Open library scene, URL | Slow creation; source closes while pending | No orphan destination or delayed success | H,C,E | READY |
| SCENE-02 | Open/tab, system-delivered App Intent | Cancel/timeout during creation; concurrent opens | Correlation preserved; no wrong destination | H,C,E | READY |
| SCENE-03 | Scene restoration after normal restart | Restored scene IDs and source ownership | No duplicate scene or wrong draft | E | READY |
| ENTRY-PROMPT | Confirmation/prompt, system-delivered Intent | Cancel the pending owned prompt | One cancelled result, no tail or success effect; keyboard recovery | W,H,C,E | READY |
| ENTRY-HTML | HTML, system-delivered Intent | Typed Unicode return | Exact response and one success in caller/history | W,H,E | READY |
| ENTRY-ARRANGE | Arrangement, system-delivered Intent | User Cancel | No committed arrangement; one cancelled result | H,C,E | READY |
| ENTRY-SAVE | Save file, system-delivered Intent | Picker Cancel | Target absent; no tail or second result | H,C,E | READY |
| ENTRY-BOOKMARK | Bookmark file API, system-delivered Intent after restart | Reuse the authorized bookmark | Exact neutral bytes, scope released and one success | H,E | PERMISSION if authorization is absent |

Rows with several subcases name a bounded family, not acceptance of untested
variants. Split the actual session into outcome-specific evidence before closing
its row. Do not claim every API option or legacy integration from this inventory.

## Controlled speech progress

[Speech permission and cleanup](speech-permission-lifetime-2026-10-22.md) adds
controlled support for SPEECH-DENY/CANCEL/LATE and MIC-DENY/CANCEL/LATE. Requested
speech denial/restriction and microphone refusal stop before capture. Old grants
cannot advance the next session. Same-turn recording cancellation rejects text
and Done. The transcription runner case checks retained writes, no later steps
or Archive, one final cleanup and a successful following action.

The cancellation/deadline regression is fixed for all three transcription phases.
These are injected driver and worker results. Native case states above remain
pending. TRANSCRIBE-01 still requires the actual production recognition timeout;
a fake-clock boundary is not that observation. No microphone was activated.

## Closure

Keep the six engine contracts partial while required cases or reference decisions
remain unresolved. Link results to their case IDs and existing dated evidence.
Update limits only after observed acceptance. Retain blocked cases explicitly.
The strict gate must not pass by deleting an obligation, removing a contract or
marking a whole contract unavailable for one blocked capability.


## Native dictation callback follow-up

The separate speech record documents a native audio-start exit and a focused
Sendable audio-tap correction. Full Core679/app793, Python80, local Debug build
and structural matrix0 pass. Strict engine remains six partial/18 diagnostics.
The corrected signed Engine QA showed Dictation. User-Cancel from the action
palette closed the panel, stopped audio, retained the marker in Inbox, omitted
tail/Archive and recorded Cancelled. This is one user-Cancel subcase of DICTATE-01.
Recognition/Done, Undo, URL/Intent speech paths, task cancellation, permission
negative paths and production timeout remain open. No row is promoted wholesale.
The usual app is unchanged. QA is closed; its neutral data remain recoverable.


## Native transcription interruption follow-up

The speech record now accepts action-palette selector Cancel and production wait
timeout while selecting audio, each with a closed panel, retained marker, no
later/success effects and one result. A fresh synthetic transcription succeeded
after each. Four persistent run IDs and recovered archived text were checked
read-only after normal QA quit. No microphone or new permission was needed.
This does not accept SPEECH permission negatives/late events or TRANSCRIBE-01:
recognition timeout is distinct from waiting in Open. Native task cancellation
and URL/Intent speech dispatch remain pending. No full contract is promoted.
The controlled follow-up adds dictation runner denial/cancel and pre-start cancel
coverage; transcription runner coverage also includes the picker stage.
