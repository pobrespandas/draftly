# Actions execution

Updated: 20 October 2026.

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
retains the existing interface. Other native capability adapters still contain
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

Callback requests register their token before opening the destination. Completion,
cancellation, and timeout remove the token. Unknown and late callbacks cannot
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


## XML-RPC asynchronous transport — 20 October 2026

The async host awaits XML-RPC through the serialized HTTP transport. Request and
response conversion share helpers with the legacy adapter. Cancellation and
timeout retain their execution result and stop later steps. Injected transport
tests cover cleanup and library gate release. Real server and native automation
checks remain pending. The legacy route still uses its synchronous adapter.
