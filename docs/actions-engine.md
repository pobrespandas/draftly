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
