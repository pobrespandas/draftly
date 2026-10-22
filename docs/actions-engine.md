# Actions execution

Updated: 22 October 2026.

## Implemented

`ActionRunner.runAsync` returns `ActionExecutionReport`. The report retains the
execution ID, root action ID, result, termination reason, and success parameters.
The existing synchronous methods remain compatible. Both routes use the same
library exclusion gate, configuration conversion, and success effects.

JavaScriptCore runs on a serial worker in the async route. Each runtime and all
JavaScript values stay on that worker. The worker releases the runtime on its
queue before the action returns. MainActor owns library, editor, and window work.
The synchronous legacy route still runs on MainActor.

Worker runtime operations check their serial queue with dispatch preconditions.
An internal optional probe reports scalar lifecycle events and queue/thread
observations. It does not expose JavaScript values. Close releases the runtime
on that queue before returning. This does not control JavaScriptCore GC timing.

The bridge exchanges JSON strings and execution and step IDs. Each request has
a unique reply token and a deadline. Cancellation releases pending worker waits
and cancels their host tasks. Duplicate replies cannot replace the first reply.
The receiver rejects closed executions, wrong steps, and expired requests.

Async script completion uses continuations. Timers schedule their next due event
on the worker queue. Generation changes invalidate timers and deadlines from
previous steps. There is no RunLoop polling in this script wait. CPU-bound
JavaScript uses the existing JavaScriptCore execution limit. Cancellation of CPU
work is bounded by that limit; it does not interrupt arbitrary instructions.

HTTP has an async URLSession transport for the new bridge. Its legacy adapter
retains the existing interface. Request timeouts default to 60 seconds and accept
positive finite values without an HTTP-specific maximum. Action and host request
deadlines still apply independently. Other native capability adapters still contain
synchronous waits. Their cancellation and permission acceptance is not closed.

Included steps use the same JavaScript context. Selected action UUIDs survive
renames. Name templates resolve when execution reaches the include. Static
references are checked before execution. Dynamic cycles fail when resolved;
prior effects remain. Included actions do not apply their own success effects.
Dynamic configuration adds missing keys without replacing existing script state.

Required configured values prompt before first use on both runners. Imported
defaults do not count as confirmation. Confirmation belongs to the root action
and records each required step identity, key, and type. New required definitions
prompt again; accepted fields stay confirmed. Static includes prepare before
root effects. Dynamic includes prepare before child effects and retain earlier
root effects on cancellation. Accepted values save atomically before execution.
A concurrent action edit rejects the stale response. Ephemeral actions do not
install themselves. Native acceptance and duplicate-key precedence remain open.

The canonical include fields are `uuid` and `name`. The archived advanced-step
reference describes identity selection and name templates. Public Directory
examples confirm those serialized keys: `https://actions.getdrafts.com/a/2P8`
and `https://actions.getdrafts.com/g/1aM`. These examples supplement field mapping;
they do not replace the archived contract. Import keeps the step UUID separate
from the included action UUID and preserves the original payload.

## App entry points

Window actions reserve execution before scheduling a Task. Batch actions process
the captured order and stop on failure or cancellation. Closing the source window
cancels its action. URLs and App Intents await the same final report. Invalid run
links return an error and select the error callback when provided. Success
callbacks use the parameters from the final report.

RunDraftActionIntent accepts an internal per-instance execution environment.
Production calls capture the current app context when perform starts. Tests inject
a temporary library and host, then call the actual perform method and runner.
They do not replace the final report or use a global test override. Public intent
parameters remain Action Name and Draft UUID. System Shortcut dispatch remains
a separate native acceptance requirement.

Automation and window actions check canonical library ownership before pending
saves or batch selection. This includes owners without a window. The runner still
acquires the same gate before execution. A busy preflight does not flush drafts.

User navigation and text changes cancel a pending window action before a delayed
script can change the new draft or overwrite user input. Synchronous script
commands expose a read-only mutation marker to the app adapter, so script-driven
navigation and Undo do not cancel their own execution.

EditorSession records the content that was loaded or saved. A stale source is
rejected before the first step; local pending text is kept. Headless executions
also retain the serialized content of stored drafts. Before
a text save, they reject concurrent content changes or deleted drafts. This
prevents stale cached drafts from replacing text or recreating a deleted note.
Access-date changes do not count as content conflicts. This guard does not
provide a transaction across external effects or full metadata conflict merging.

## Acceptance

Automatic tests cover shared context, original action scripts on both routes,
worker responsiveness, host reply lifetime, completion, promise rejection, timers,
timeouts, cancellation, queues, includes, import preservation, library exclusion,
window scheduling, batch behavior, and URL target validation. HTTP tests use an
isolated URLProtocol fixture, not an external server.

Computer Use ran a separate app with a temporary local library. A delayed action
left panel controls available, then changed the editor to neutral Unicode text.
Native Undo restored the exact source. A second action was cancelled by closing
its window. Execution History showed Success and Cancelled for those actions.
Typing during a pending action cancelled that action and retained the new user
text. The user library and normal installed app were not replaced. No screenshots were
stored. These observations do not prove external callbacks or App Intent delivery.

## Remaining work

- Complete URL/App Intent timeout, busy, concurrency, window-close variants, and native callback timeout.
- Complete cancellation and deadlines in remaining native capability adapters.
- Verify HTTP redirects and socket behavior with a local server.
- Complete contract cases and native acceptance in the engine matrix.
- Keep the strict engine, core, and global checks open until their evidence passes.
- Continue the approved API, integration, inspector, personalization, visual, data,
  and CloudKit roadmap. This delivery does not close all Mac parity.

The auditor requires fourteen named engine contracts. `--scope engine` checks
that scope alone. Missing entries cannot make the strict parity check pass.

## Recorded automatic result

The earlier async migration run passed 178 app tests in 31 suites and 301 core
tests in 38 suites. The native-wait follow-up passed 192 app tests in 33 suites
and 306 core tests in 40 suites. Python tooling passed 28 tests. The unsigned local Xcode build and
normal matrix validation passed. Strict parity remains open. Test totals describe
regressions, not a compatibility percentage.

## Native asynchronous waits

The async host boundary accepts and returns JSON strings. The native host opts in
for callback URLs, shell scripts, and Shortcuts. First-party callback and Shortcut
steps use that boundary too. Legacy entry points keep their synchronous adapters.

Callback requests register their token and absolute deadline before opening the
destination. Delivery checks that deadline even if the timeout task has not run.
Opening the destination consumes the same wait budget. Completion, cancellation,
and timeout remove the token. Unknown and late callbacks cannot
complete another request. A private bundle setting can select an isolated QA
callback scheme; the normal app still uses `draftly`.

Process waits use termination handlers. Output uses temporary files, so a full pipe
cannot block the child. Cancellation sends SIGTERM to the isolated process group,
then SIGKILL after a short grace period. It waits for the direct child to exit.
Descendants that deliberately leave that process group are not contained.

The runner keeps the library reserved until supported host operations finish their
cleanup. Hosts must suspend and cooperate with cancellation. A host that ignores
cancellation keeps the library reserved; its late reply cannot resume a closed
script. Other native adapters still need an audit of their synchronous waits.
Computer Use verified real callback success, cancellation, error, and a late reply
after user cancellation. Scene routing now keeps the original window. Native
callback timeout and native Shortcut success remain pending. Real App Intents
passed success, delayed failure, and cancellation; other variants remain pending.
Calendar and Reminders authorization and query waits also use the async boundary;
their real permission and persistence checks remain pending. Event editing now uses an async panel in the new route;
its real dialog and persistence acceptance remain pending. See docs/validation.md for the accepted cases.

Speech and location now have cancellable async adapters with injected tests. Their
real system acceptance remains pending. The current regression run passed 229 app
and 309 core tests, plus the unsigned local build. Canonical persistent-store URLs
now identify process-local library exclusion, including symlink paths. This does
not provide cross-process locking or full cache coherence between store instances.

## Additional async native waits — 20 October 2026

The new host route also supports prompts, confirmation, alerts, file transcription,
calendar editing, event creation, and Apple model responses. Prompts share their
field builders with the legacy presenter. Prompt steps share payload and result
mapping across both runners. Model tools have request and session lifetime guards;
core tool mutations use the script mutation marker and update saved snapshots.

Injected tests check cancellation and cleanup without visible windows or system
permissions. The unsigned build passed. Real dialog keyboard behavior, EventKit
persistence, transcription, and Apple model use remain pending. Live dictation and
other native synchronous adapters still need review. See docs/validation.md.


## Dictation and AppleScript waits — 20 October 2026

Live dictation and AppleScript now use the async host route. Dictation uses a
permission and capture state machine with a nonmodal panel. Its system acceptance
remains pending. AppleScript uses a child mode of the app executable before app
startup. JSON results preserve null and native records; unknown coded property
names remain four-character keys. Cancellation terminates and reaps the helper.
Real QA verified neutral AppleScript success, typing cancellation, and subsequent
actions. The external URL confirmation also suspends instead of running a modal
session. See docs/validation.md for exact accepted cases and the corrected Debug
bundle preparation. Mail, Messages, HTML, file panels, printing, and arrangement
still contain waits that need review. Strict engine acceptance remains open.

## HTML, file panels, and composition — 20 October 2026

The async host now supports interactive HTML, export panels, bookmark selection,
and native Mail/Message composition. First-party steps use the same awaited
boundary. File and message payload rules are shared with the legacy executor.
Local file I/O still runs synchronously; this delivery removes panel waits, not
all disk work from MainActor.

HTML requests finish once. Completion detaches WebKit handlers and navigation
callbacks. Cancel restores the editor, and late messages cannot change results.
File selection checks cancellation and its deadline before storing a bookmark or
writing. Export checks canonical paths, including symlinks and /var aliases.

Composition uses service callbacks rather than RunLoop polling. Unsupported HTML,
background sending, Reply-To, CC, and BCC options fail explicitly in the new path.
They are implementation limits, not accepted full Mail parity. Native sent means
that the service reported sharing; it does not prove network delivery. Cancel or
timeout stops waiting and detaches callbacks. macOS exposes no service API to
close or recall an external composer already transferred to another app.

Caught native interruptions cannot start more host calls. Absolute deadlines also
reject replies that arrive before a delayed timer task can run. Exact tests and
real HTML/export acceptance are in docs/validation.md. Printing, arrangement,
sharing outcomes, and remaining native capability acceptance still need work.

## Printing, sharing, and arrangement — 20 October 2026

The new route awaits print and sharing callbacks. Print accepts Text or HTML and
validates string or numeric margins in points. Its default margin is 72 points.
Cancel closes only the request's own sheet. A spooled print job cannot be recalled.
AppKit's Boolean print callback does not distinguish every failure from cancel.

Sharing waits for service completion. Closing the picker returns false. An action
step treats false as cancellation and stops later steps and success effects. A
script can inspect the Boolean result. Shared files remain available until the
service callback, including after an action timeout. If a service never calls
back, the file has no confirmed cleanup time. It can remain after process exit.
macOS cannot recall work
already transferred to another app.

Editor.arrange waits and returns the arranged text. User Cancel returns its exact
input. Editor.showArrange returns immediately. Its window owns the pending task.
A result applies only to the captured draft and unchanged content. Navigation,
window cancellation, and user edits invalidate the pending request. Accepted
changes use the editor's Undo path. Legacy synchronous adapters remain available.

Native checks and exact automatic results are recorded separately in validation.
Strict engine acceptance remains open. Location templates and template-directory
access still need review for native waits during synchronous template rendering.

## Awaited template data — 20 October 2026

The new runner awaits location and template-file requests at the point of use.
This includes nested templates, included-action names, script processTemplate,
URLs, and step fields. Escaped tags and custom overrides do not request native
data. Static tags and final transformations share their rules with the legacy
renderer. Recursion retains the existing limit of 20.

Pure step builders replay resolved fields by call index. A field renders once;
identical sources in different fields can return different values. The helper
rejects a changed render order. Create Draft shares one payload builder across
both routes. Native template errors stop steps and success effects. Real location
and persistent folder permission checks remain separate acceptance work.

Arrange accepts text through automation without borrowing a window's editor.
Window-bound operations still require a window adapter. Print layout now uses
paper size, margins, scale, and fitted text height. HTML import specifies UTF-8.
The neutral native preview shows one page. Actual print output remains pending.

## Automation editor context and dictation — 20 October 2026

Automation resolves its editor context once. It prefers a visible matching key
window, then a matching main window, then another visible matching window. It
uses that model's runner and editor. It never lends another draft's UI to a
separate editor. Without a matching window, independent operations use the
headless route. Window-bound operations still require a matching context.

A busy model rejects the request before any pending edits are saved. Rejected
starts have a final report with a separate execution identity. App Intents retain
the final reason and result in a localized error. URL callbacks retain their
existing success, cancel, and error destinations. The URL route does not select
the same visible result again; this preserves nonblocking editor panels.

Draft opening requests survive window startup and save failure. A new window or
tab request excludes models that already exist. A closed destination cannot hand
its pending request to another model. Missing targets report an error.

showDictate now owns an async window session. It returns immediately and does not
poll the RunLoop. It checks captured text, selection, draft identity, and stored
content before insertion. A changed destination sends accepted speech to the
recovery flow. Cancel and owner release stop the request. Native voice and close
acceptance remain separate from injected automatic tests.

## Startup cancellation and deadline boundaries — 20 October 2026

An owner-close subscription now covers the interval before the automation child
starts. Close and parent cancellation cancel that child; cleanup removes the
subscription. The worker validates its synchronous deadline before combining
limits. Invalid synchronous limits cannot be hidden by a valid async limit.

The unknown disabled import engine contract passed native import, inspector,
export, and execution checks, plus the dedicated backup/restore test. It is one
complete engine contract. The other thirteen remain partial. Independent window
metadata confirmed no visible reopen after source close; direct CUA observation
caused the earlier extra window in a no-action control. See validation for scope.

## Unhandled promise rejections

ActionScriptRuntime installs JavaScriptCore's engine rejection callback. It
observes discarded promises and promises created by async functions without
replacing Promise. Normal catch handlers remain valid. The callback runs on the
runtime's owning queue. Step completion and runtime close invalidate its epoch.

This uses JSGlobalContextSetUnhandledRejectionCallback from WebKit's
[private JSC header](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextRefPrivate.h).
The runtime resolves the symbol and reports an explicit error if the system
cannot supply or install it. This is a system SPI dependency, like the existing
execution-time-limit support. Personal development distribution remains the
current scope; public distribution needs its own review.


## Mustache execution context — 20 October 2026

Action Mustache rendering now uses the action's existing JavaScript context.
On the async route it stays on the serial worker and uses the script deadline.
Template file reads still use the host. JSON conversion keeps prior value and
Date behavior. The standalone Swift renderer and legacy host operation remain
available. Automatic tests cover no-host rendering, timeout, and reuse after
timeout. Native responsiveness and directory permission acceptance remain open.


## XML-RPC transport — 21 October 2026

The async host awaits XML-RPC through the serialized HTTP transport. Request and
response conversion share helpers with the legacy adapter. Cancellation and
timeout retain their execution result and stop later steps. Injected transport
tests cover cleanup and library gate release. The legacy route keeps its
synchronous adapter.

XML-RPC requests set the internal includeResponseBytes flag. Without a declared
HTTP charset, the transport can add responseBodyBase64 beside value in its
internal response envelope. XMLParser receives those original bytes and detects
the XML declaration or BOM. The extra field stays outside HTTPResponse and
XMLRPCResponse. Ordinary HTTP requests omit it.

A declared HTTP charset keeps priority. That path decodes text through HTTP,
then aligns the XML declaration with its UTF-8 conversion. Older injected
transports with only responseText still use that path. Invalid present base64
fails explicitly. An HTTP failure cannot become XML-RPC success through its body.

Real loopback tests cover both engines, declared charsets, declaration/BOM
encoding detection, request wire format, faults, malformed XML and disconnects.
Native automation, JavaScript date/binary mapping, full grammar and remaining
invalid inputs still require their specific acceptance. See docs/validation.md
and the API matrix for the exact scope.

## Inspector-created configured values — 21 October 2026

Implemented: the add-step menu now includes configurationKey. New steps have
editable key, name, description, value type, type-specific default, example and
required-configuration controls. Text supports multiple lines. Boolean defaults
use a switch. Unknown types and fields remain visible and preserved. Imported
defaultValue remains separate and its precedence is shown. Reading a step does
not fill missing imported fields. Cancel keeps the existing temporary-copy rule.
New steps require first-use configuration by editor policy; the archived reference
does not specify that initial toggle state. An omitted new name permits the
existing key-label fallback. Existing imported empty names are not rewritten.

Automatic: the editing-copy and descriptor cases passed. The new flow test uses
the actual runner on both routes for string, text, false, zero and cancellation.
It verifies typed script values, unchanged definitions, confirmation reuse,
retained text, no Archive after cancel and library-gate release. Thirty focused
methods passed across the app and initial-configuration suites. The first full
concurrent Core run had five timeout issues in unchanged WorkerPromiseEpochTests
and MustacheWorkerTests. The four affected methods passed in an isolated serial
run. Complete serial verification then passed 646 Core and 637 app methods with
inventory/report matching. No timeout or retry policy changed. After omitting the
new empty name, all 15 affected app methods passed again, including key-label
fallback. Final local Debug and signed Release passed. Structural API validation
reported zero errors; this is not parity acceptance.

Verified in use: a fresh local Functional QA app created a neutral draft and an
action through the inspector. Added configurationKey, entered its fields and
moved it before the script. Cancel at first configuration kept the draft intact
and reported cancellation. A second run asked again. Accepted Unicode text reached
the script and completed. After normal Quit, QA was refreshed with the final
build while keeping its identity and library. The action and text survived. A new
run reused the accepted value without another prompt and reported completion.
Initial QA executable SHA256:
309efa31eec68401a5b49a0b372a3888c9d5130804834f8af8b4a0f4e1de7bf3.
Final restart executable SHA256:
860277f92bd3e264a91cd5be536bb170f770062115c21a31b7a530a4ff744413.
QA quit normally. It publishes no Services or URL schemes and uses no CloudKit.
The habitual package and personal data were not changed.

Pending: native typed-control variants, configuration via other entry points and
shared include-key precedence remain separate. No engine record is promoted by
this inspector flow alone. The prior UI Flows QA temporary package, library and
bookmark folder were absent at this session start. Its old bookmark-restart check
cannot be accepted from this fresh QA session. Recreate neutral fixtures for it.
The next concrete inspector defect is the hidden includeAction target UUID.

## Editable included-action identity — 21 October 2026

Implemented: the step inspector exposes the included action UUID and name even
when an includeAction has no stored fields. Only this step treats values.uuid
as an editable target. Other steps still hide that metadata key. The UI labels
it Action UUID and explains name-template fallback. It does not modify the
step's own identity, imported payload or unknown fields.

Automatic: the descriptor regression failed twice before the fix: the imported
UUID was hidden and an empty include had no target controls. It now passes.
The new editing flow saves and exports an edited parent, preserves its step ID
and unknown fields, then runs the selected UUID despite a stale matching name.
Both runners passed. Focused inspector/editing/include suites passed. All 639
app methods passed serially; report identities matched the inventory. The
unchanged Core suite retains its earlier complete serial 646 result. Local
Debug and signed Release passed. The prior concurrent worker timeouts remain
recorded in the preceding section; no test deadlines changed.

Verified in use: imported two neutral helpers and a parent with a target UUID,
old name and futureOption. The inspector displayed the UUID and futureOption.
Changed the UUID and canceled. Reopening retained the old target. Changed it
again and saved. Execution from the action list returned Selected café 🐼 from
the new target, although the old name remained. The app reported completion.
QA executable SHA256:
77aa984798a0eb6c5602f9ecd73c3ad6e5e83b4be482dd892c1a574195f05c2e.
QA quit normally. The fixture and library remain outside Git. No personal app,
services, permissions or CloudKit data changed.

Pending: this field fix does not provide a visual action picker or settle shared
configuration precedence. Other inspector options and native capability lifetime
checks remain open. Continue the five functional blocks approved by the user.

## Native action bookmark restart — 21 October 2026

No production change was needed. The reproducible fixture is
scripts/fixtures/bookmark-restart-actions.json. Prepare a neutral folder with
source.txt containing Neutral bookmark source — café 🐼 followed by a newline.
Do not use a personal folder. The action reads source.txt, checks the missing.txt
error, writes result.txt, checks exact Unicode readback and adds a success
parameter. It does not change the draft.

Verified in use on Functional QA executable
77aa984798a0eb6c5602f9ecd73c3ad6e5e83b4be482dd892c1a574195f05c2e:
- Imported the fixture through File Import. Started from a neutral draft.
- Canceled the first folder picker. The app reported cancellation and kept the
  draft text. The next run requested a folder again.
- Selected only the neutral BookmarkQA folder. The action reported read/write
  success. File inspection confirmed exact source/result text and no missing.txt.
- Quit normally and confirmed the process absent. Reopened the same package and
  library. Loaded the existing draft and ran the same action. It completed
  without a folder picker. Execution History contained Cancelled, Success and
  Success for these three attempts. QA then quit normally.

The QA app uses no CloudKit, Services or URL scheme. Python tooling passed all
68 tests, including fixture identity checks. No Swift source changed after the
preceding validated builds. The result accepts this UI action-host bookmark path
and restart, not Settings geometry, denied/lost permissions, Forget, iCloud Drive,
owner-close cleanup or capability-specific URL/Intent variants. The strict engine
records remain partial where those obligations remain open.

## Create Draft editor destination — 21 October 2026

Implemented: Create Draft now has one Open in Editor switch, including imported
steps without the key. The read value matches the existing executor: only the
literal false creates in the background. Reading imported or unknown values
does not rewrite them. New steps explicitly retain the existing true default.
The archived utility-step reference describes this option but does not fix its
initial UI state. Other Create Draft fields remain separate inspector work.

Automatic: the copy-to-save-to-run test covers both editor destinations on both
runners. It checks new identity, saved step identity, source content, selection,
access date, reload and imported disabled steps without this key. Background
creation leaves access date unknown. Foreground creation loads the new note.
Descriptor tests cover missing, true, false and unknown imported strings. All
21 focused methods passed across the app and core step suites. All 641 app
methods passed serially, with report/inventory matching. The unchanged Core
suite retains the preceding complete serial 646 result. Local Debug and signed
Release passed. No deadline, signing identity or storage format changed.

Verified in use: created QA Create Draft in background in the inspector. Added
createDraft, disabled Open in Editor and entered neutral Unicode content. Saved
and ran it from Actions with café 🐼 selected in the source draft. A new list
row contained the requested complete text. The source editor and Unicode
selection stayed unchanged. The app reported completion. QA executable SHA256:
31b8367402a745a9214a0fded515cc66172c8e6cb7acc982bbc26907e9fcc6f3.
QA quit normally. Native foreground variants and other step options are not
accepted by this one background check. Personal data and the habitual app remain
unchanged. Continue editor/prompt and other inspector contracts separately.

## SelectPrompt search arrow navigation — 21 October 2026

Implemented: ordinary SelectPrompt now accepts Up and Down from its initially
focused Search field. It uses the existing filtered-index mapping and clamps at
the first/last visible item. Draft selection retains its existing Escape route.
Ordinary SelectPrompt leaves Escape and Return with the native alert. Unrelated
controls are not intercepted. No scripting signature or stored format changed.

The previous restriction was explicit and characterized by a test. Before the
change, native Down from Search kept One selected and Search focused. Escape
canceled and kept the neutral draft. This is a functional improvement; no new
comparison with Drafts was made, and it is not evidence of a Drafts mismatch.

Automatic: a new ordinary-search regression failed before the change. It covers
Unicode title/subtitle filtering, original indices, both directions, boundaries,
empty results, retained query, native Escape/Return and foreign controls. The
existing draft-selection test now permits ordinary arrow navigation while
retaining its Escape assertion. Forty-two focused app/core prompt methods passed.
All 642 app methods passed serially with inventory/report matching. The unchanged
Core suite retains the preceding full serial 646 result. Local Debug and signed
Release passed. Python remains 68 from this session. The concurrent worker
issues described above remain recorded; no deadlines or retry policy changed.

Verified in use on QA executable
c089bbc5348f6e2ada8ff8ac7b6d7170ea0f8039d4a2631b33c328613ab30839:
- Reused scripts/fixtures/engine-prompt-actions.json and a neutral existing draft.
- Search had initial focus. Down selected Two; Up selected One. Focus stayed in
  Search. Down followed by Return completed and the script displayed Selected: two.
- Ran it again and pressed Escape. It reported cancellation and retained
  Selected: two. QA quit normally. The habitual app remained unchanged.

Pending: other prompt options, interruption paths and the remaining editor,
inspector, integration and Settings contracts retain their own acceptance. This
check does not close the five functional blocks or the complete cloning plan.

## Configure Window inspector controls — 22 October 2026

Implemented: a new or imported configureWindow step exposes Draft List, Action
List, Filters, Action Bar, Tag Entry, Pin Current Draft and Link Mode. Each
control supports Unchanged, On and Off. Choosing Unchanged removes only that
key. Imported aliases are normalized for display only. Unknown values remain
visible as Imported and are not rewritten when the editor opens. Three reference
fields remain available even when absent: Workspace, action list group and action
bar group. The adapter and inspector share the supported keys and Boolean values.
The executor's accepted values, case sensitivity and errors did not change.

Automatic: 24 focused app methods passed. Ten new flow cases use temporary
preferences, an in-memory library and both actual runners. They cover all seven
controls, all three references, Workspace name/UUID lookup, copy discard, save,
reload, unknown fields, stable identities and missing-reference preflight before
any change. Text, UTF-16 selection and focus stay intact. Descriptor tests cover
missing references and display-only aliases. All 645 app methods passed serially;
report identities matched discovery. The unchanged Core suite retains the prior
646 serial result. Local Debug and signed Release passed. Python remains 68 from
the previous session; no Python source changed. Prior concurrent worker timeouts
stay documented. No deadline, retry, identity or storage format changed.

Verified in use: created QA Configure Window controls through the new-step menu.
The seven controls initially showed Unchanged. Saved Action List On, Action Bar
Off, Tag Entry Off, Pin Current Draft On, list group Imported and bar group
General. Execution reported completion, showed the Imported list, hid the bar
and tag entry, and displayed the active pin. Source text and café 🐼 selection
remained. Undo removed the original paste and Redo restored the exact text.
Reopening the action retained its saved options. Entered a missing Workspace in
the temporary copy and canceled. Reopening again showed that field empty and
kept the saved options. A user focus change required one fresh accessibility
snapshot; no forced exit was used. QA quit normally.

QA executable SHA256:
3787f3f57ce616a58ef87df4d5c53bcc8c9679baabcde48ac163b6c2ad588d25.
The habitual app and personal data remain unchanged. This check does not accept
native Workspace loading, every toggle combination, first-party import variants
or full step parity. Those obligations remain explicit in the API matrix.

## First-party Prompt inspector fields — 22 October 2026

Implemented: new Prompt steps expose Key, Title, Message, Buttons, Text Field
Default, Include Text Field and Include Cancel Button. The defaults match the
archived advanced-step reference: prompt, Prompt, empty message, OK, empty text,
text field off and Cancel on. Message supports multiple lines and tag insertion.
Buttons use the documented pipe separator. Missing imported fields display the
default without inserting keys. Explicit empty fields, aliases and unknown data
remain unchanged until edited. These defaults apply only to newly added steps.

Automatic: 26 focused methods passed. Ten new flow cases cover both runners:
documented defaults, custom tags, second-button selection, rendered title/message
and text, cancellation before a tail and an already queued action, and invalid
empty keys/buttons before the host or success effects. Copy discard, save/reload,
IDs and unknown imported data also passed. All 650 app methods passed serially;
report identities matched discovery. The unchanged Core suite retains the prior
646 serial result. Local Debug and signed Release passed. No Python source
changed; the earlier 68 Python result remains separate. No deadlines changed.

Verified in use: created QA Prompt step response in the inspector. Initial
controls showed OK, prompt, Prompt, text off and Cancel on. Set a custom key,
title, two-line Unicode message, First|Second buttons and [[title]] text default.
Enabled text and added a background Create Draft tail using choice_button and
choice_text tags. The native prompt displayed all fields and rendered the title
into its text input. Entered discarded text and canceled: eight drafts remained,
the source stayed unchanged and the action reported cancellation. Repeating the
run restored the configured text default. Accepted Second with neutral Unicode
text: the ninth draft contained exactly Second: Accepted neutral café 🐼, while
the source editor stayed unchanged. The action reported completion. QA quit
normally and its process was confirmed absent.

QA executable SHA256:
689fee734f176cf9ac196484bbe17152cc7d6b8c7ea508aed6f9dd6c352d57f0.
The habitual app, personal data, Services and CloudKit were not changed. Native
Cancel-off/text-off variants, interruption/timeout paths and full imported step
parity remain separate. This does not close Prompt's entire step acceptance or
the five functional blocks. Continue the remaining inspector and integration
contracts with specific evidence.

## App Intent final failure regression — 22 October 2026

Automatic: the actual RunDraftActionIntent.perform method now has two explicit
failure cases: a rejected promise and context.fail after script.complete. Both
retain a prior persisted Unicode edit, stop the tail, skip Archive, remove success
parameters, return the matching execution error, and release the window for a
following successful Intent with a new execution identity. Eight Intent methods
passed, including these two parameter cases. The prior focused baseline passed
24 app methods and 18 Core methods. No production behavior or deadline changed.

Native: no new system Shortcut or permission acceptance was performed. These
headless tests do not accept system dispatch or any native capability route.
The remaining native checklist and strict engine gate stay open. The habitual
application was not replaced. Continue with the unresolved capability-specific
cancel, timeout, owner-close and late-result cases in engine-native-checklist.md.

Validation: local Debug build passed. API matrix structural check reported zero
errors. This structural result does not close the strict compatibility gate.

## Cancellation before callback cleanup — 22 October 2026

A new deterministic headless case cancelled an active callback task and delivered
its reply in the same MainActor turn, before queued cleanup could run. The old
router accepted that reply and returned success. The regression failed with both
assertions. The first test draft needed a Sendable return value before execution;
that compile correction was separate from the observed runtime failure.

ActionCallbackRouter now keeps a locked cancellation flag per pending request.
The cancellation handler sets it immediately before scheduling MainActor cleanup.
Receive rejects a cancelled request; finalization releases its continuation with
CancellationError. The resumed caller also checks task cancellation before it
returns response data. Timer and dictionary cleanup remain on MainActor. The
legacy synchronous path and public scripting contract stay unchanged.

Automatic: the regression and all22 focused callback/Prompt/Intent methods passed.
All709 app methods passed serially; XML results matched the discovered inventory.
Local Debug build and matrix structural validation passed. Core source did not
change. No deadlines or retry rules changed. No new native session was performed
for this correction. Earlier native callbacks retain their tested-image scope.
This does not close the six partial engine contracts or native-route checklist.

## Waited Shortcut process interruption — 22 October 2026

The waited Shortcut adapter now has explicit cancellation and timeout cases.
A neutral injected executable starts a real local process and waits on a fixture
release file. The test waits for its started marker, confirms the transferred
input file exists, then cancels the task or awaits the configured test timeout.
Both cases require the distinct error, no returned result, terminated process,
removed input directory and absence of the completion marker. The executable
uses no installed Shortcut, permissions, sound, windows or personal data.

All17 native process/Shortcut methods in two suites passed, including both new
parameter cases. Local Debug build and matrix structural check passed. No
production source or production deadline changed. The prior full app709 result
remains a prior result; it is not a rerun of this new test.

This accepts the actual adapter's process and input ownership under interruption
with an injected executable. It does not accept /usr/bin/shortcuts dispatch,
Shortcuts service cleanup, UI/URL/Intent capability-specific cancellation or a
real Shortcut's external effects. Those native obligations remain open in
engine-native-checklist.md. No new manual session or habitual app update occurred.

## File selection cancellation before cleanup — 22 October 2026

A deterministic test cancelled file selection and delivered its accepted URL in
the same MainActor turn, before cancellation cleanup could run. The old selector
returned the URL instead of throwing. The regression failed before the fix.
NativeFileSelectionRequest.select now checks task cancellation after its wait
and before returning any selection. Existing save/bookmark adapters retain their
own cancellation checks, so this closes the selector boundary without removing
write protection or adding a new UI flow.

The new test also delivers a duplicate completion and requires exactly one panel
close. Focused17 app and6 Core methods passed, including cancellation without
writes or persisted bookmarks. All711 app methods passed serially and matched
XML report inventory. Local Debug build and matrix structural check passed.
No Core source or deadline changed. No new manual panel session was performed;
real lost-access, owner-close and late OS panel delivery remain separate in the
native checklist. The habitual app was not replaced.

## Intent pending-save rejection and recovery — 22 October 2026

The actual RunDraftActionIntent.perform method now has separate pending-save
cases for the target draft and an unrelated editor draft. An injected storage
failure must reach the caller before any action starts. Assertions retain the
specific storage diagnostic in the library, the visible pending Unicode text,
selection identity and dirty state. Stored text stays unchanged. No execution
history or library reservation is created. Removing the injected failure and
performing the same Intent succeeds. The unrelated draft's pending text saves
before the target runs. No partial rollback is promised.

All14 focused Intent and automation safety methods passed. Local Debug build and
matrix structural validation passed. Production source did not change. No manual
system Intent or storage-permission session was performed; the test invokes the
actual Intent method with an isolated environment. Prior full app711 remains a
prior run, not coverage of this new method. The engine strict gate stays open.

## Integrated engine regression — 22 October 2026

At 8f50a87 the repository was clean. scripts/run-swift-tests.py completed both
Swift targets and checked every XML identity against discovery: Core674 and
app712 methods passed. App tests ran serially. All68 Python tests passed.
No retries, deadline changes or visible UI tests were used. The local build from
the same production source had passed in the prior pending-save checkpoint.

The structural matrix check remains distinct from acceptance. The strict engine
check returned18 errors across six partial contracts: included configuration
precedence, separator group import, worker/native lifetime, host lifetime, task
cancellation and common entries. Their native/reference obligations remain in
engine-native-checklist.md. These suite totals do not measure compatibility.

The duplicate Action.find issue is not currently open. The archived Action page
explicitly specifies the first found name. ActionLookupContractTests and the
21 October native deterministic Action.find record already verify exact names,
UUID tie order, restart and backup behavior. URL and Intent lookup currently use
the same loaded first-match catalog. No ambiguity rejection or new lookup rule
was introduced. This audit corrects the continuation direction, not the contract.

No production source, installed app or native state changed in this checkpoint.
Continue the capability-specific native lifetime checks, including external
composition handoff/cancel behavior, and the outstanding reference comparisons.

## Mail delivery result correction — 22 October 2026

Native QA exposed a false sent result when NSSharingService only opened a Mail
composer. The current Mail.send adapter now fails explicitly before opening that
service. This removes false action success; confirmed Mail delivery remains
partial. It is not a system-wide unavailable classification. Full app713, local
build and native corrected error/recovery passed. See docs/validation.md, Mail
handoff is not delivery. No mail was sent; habitual app unchanged.

## Mail rejection through final reports — 22 October 2026

Specific runner cases now exercise the actual rejecting Mail adapter through both
legacy and worker execution, for both a Mail step and Mail.send scripting. They
require an error report, retained persisted Unicode text, no tail or Archive,
empty success parameters and an Error history entry. A following action succeeds
with a different execution identity. The actual Intent.perform method also
requires a typed error, retained prior effects and released library ownership.
Factories prevent any real sharing service from opening, including on failure.

All19 focused message/Intent methods passed, including the four runner parameter
cases and the Intent boundary. Local Debug build and matrix structure passed.
No production source changed. The prior full app713 run remains separate and
predates these two new methods. Native corrected URL evidence from the previous
checkpoint remains valid for unchanged production. Confirmed Mail delivery is
still partial; this only accepts truthful failure propagation and recovery.

## Speech notice cancellation — 22 October 2026

The asynchronous speech adapter checks task cancellation after both notice
responses. A cancelled task cannot accept a completion response or treat a
rejected confirmation as a normal false result. Playback cleanup remains
unchanged. Silent driver and presenter tests cover these boundaries. Native
synthesis and panel lifetime checks remain separate acceptance work.

## Process exit deadline — 22 October 2026

The process executor records an absolute deadline before launch. It checks that
deadline before accepting termination as a result. A late termination enters
the same interruption path as the timeout task. That path terminates the
isolated process group and completes cleanup before returning timeout.
An explicit launch failure keeps its original error.

Controlled-clock tests cover exit before, at and after the deadline. A real
parent/child fixture also checks that expiry after parent exit stops a remaining
child that ignores SIGTERM. These tests use temporary files and local processes.
They do not accept system-delivered Shortcuts or App Intent behavior.

## Isolated speech synthesis — 22 October 2026

The async speech route uses a private helper mode in the Draftly executable.
The launcher handles this mode before preferences, controllers or SwiftUI start.
Only the helper creates NSSpeechSynthesizer. Request files retain exact voice
identities, UTF-8 text and rate. The helper returns a typed Boolean or error.
Confirmation and completion notices remain in the parent app.

The helper receives completion through the native delegate. Its event loop uses
[CFRunLoopRun](https://developer.apple.com/documentation/corefoundation/cfrunlooprun())
and stops on delegate completion. It does not poll the parent event loop.
A blocked synthesis call or destructor cannot block the parent MainActor.

NativeProcessExecutor owns the helper deadline and process group. Cancellation
awaits helper termination and escalation cleanup before it releases the playback
continuation. Input files remain private until that cleanup returns. Timeout
keeps its typed reason. A failed helper cannot show a completion notice.
The legacy synchronous adapter is unchanged; this section describes the async
route. The operating system owns its shared audio services. Draftly never kills
those services during cleanup. Audible completion needs separate verification.

## Process cancellation at exit delivery — 22 October 2026

Waited processes record task cancellation synchronously in a locked flag.
The MainActor interruption task still owns process signals and cleanup.
Termination delivery checks the flag before accepting a status, so queued
cleanup cannot lose to a completed parent. If descendants remain, the executor
terminates their isolated process group before returning cancellation.
A second cancellation check before spawn prevents a cancelled launch from
starting a process. The caller also checks cancellation after a normal resume.

Detached launches keep their separate lifetime. They do not use the waited
operation's cancellation handler. Their existing ownership tests still apply.
The parent-exit regression tests share a fixture; expiry and cancellation keep
separate assertions and test identities.

## Print cancellation at callback delivery — 22 October 2026

The asynchronous print wait records task cancellation before it schedules
MainActor cleanup. A callback cannot return a normal true or false result
after that cancellation. The wait detaches callbacks and cancels only its
owned presentation before it returns CancellationError. The caller also
checks task cancellation after a normal resume. Duplicate or late callbacks
cannot repeat cleanup. This does not recall a print job already delivered
to the operating system or promise a rollback of completed external effects.

## Apple model request boundaries — 22 October 2026

Async model requests capture an absolute deadline at creation. Generation, tool
access and response delivery check that deadline. Cancellation records a locked
flag before MainActor cleanup is queued. A cancelled request cannot authorize a
tool during that gap. Cleanup still waits for the owned operation and discards
the failed session. The legacy synchronous route is unchanged.

Injected clock and backend tests cover the boundary and recovery without model
generation or library writes. Native generation remains blocked by system
readiness. These tests do not accept native model cancellation or tool cleanup.

## Owned asynchronous print windows — 22 October 2026

WindowModel binds its native host to its own window through a weak closure.
Async printing uses that owner after external confirmations. It does not require
the global key window. If the owner is absent or no longer visible, printing
fails before opening a panel. An ownerless native host cannot borrow another
window. The request helper keeps its current-window fallback only when no owner
provider is supplied. The legacy synchronous print path is unchanged.

## Sharing discovery boundaries — 22 October 2026

The async sharing deadline starts before file preparation and service discovery.
The request checks cancellation and expiry before and after service discovery.
A cancelled discovery cannot open the picker or become an unavailable-service
error. An expired discovery cannot reset the timeout. The timer waits only for
the remaining budget. Prepared files are removed when no service owns them.
Files handed to a service still remain until that service finishes.

Controlled driver and clock tests cover these boundaries without system sharing
services or visible windows. They do not accept native service interruption or
window ownership. The later owned-sharing check below covers owner binding.

## Owned sharing windows — 22 October 2026

The native host now supplies its action window to sharing and printing through
one weak owner closure. Sharing stores that window weakly and checks visibility
before discovery and presentation. An ownerless host cannot borrow another
window. Direct helper calls keep their previous current-window default. Owner
failure removes any prepared file. Service handoff leases stay unchanged.
