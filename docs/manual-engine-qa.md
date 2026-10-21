# Manual engine callback checks

Run these checks in a separate Computer Use session. Automated tests stay in the
background. Use a local QA library and neutral text.

## Latest owner-selection acceptance

The 21 October 2026 check in docs/validation.md verifies actual App Intent
ownership with two windows on the same draft. Both activation orders passed.
Use engine-window-owner-actions.json and neutral text to repeat that case.
This acceptance does not cover every native capability lifetime.

## Prepare the apps

Copy a fresh local Draftly build to a new QA app bundle under `~/Applications`.
Keep the installed Draftly app unchanged. For Debug updates, copy every file from
Contents/MacOS, including Draftly.debug.dylib and __preview.dylib. Replacing only
the launcher leaves old code. Compare each source and destination hash before
signing. Preserve the isolated Info.plist. Verify the complete signed bundle.
For later updates, use `scripts/refresh-engine-qa.py SOURCE_APP QA_APP --identity
"Apple Development identity"`. It requires an existing isolated bundle and an
absent QA process. It refreshes runtime files and resources, keeps Info.plist,
checks copied hashes, signs, and verifies. Its process check normalizes executable
paths, including /var and /private/var aliases. It rejects the habitual app and
normal URL scheme.

Set these Info.plist values on the copy:

- `CFBundleIdentifier`: `com.andrestobelem.draftly.engine-qa`
- `DraftlyUITesting`: true
- `DraftlyUITestingLibraryID`: a new UUID; retain it for the whole session
- `DraftlyCallbackScheme`: `draftly-engine-qa`
- `CFBundleURLTypes`: register only `draftly-engine-qa`

Build `scripts/qa-callback-helper.swift` as an AppKit executable in a separate
`Draftly Callback Helper.app`. Use deployment target macOS 26 or later. Its bundle
identifier is `com.andrestobelem.draftly.callback-helper`; its executable name is
`CallbackHelper`. Set `LSUIElement` to false and register only `draftly-engine-echo`.
Sign the QA app with the existing Apple Development identity. A Team ID is
required for the recorded App Intent check. Sign the helper locally. Register
both bundles with Launch Services.

Keep the helper under `~/Applications`. In the recorded session, Launch Services
listed the `/tmp` helper but NSWorkspace could not resolve its URL scheme. Moving
the test bundles out of the temporary directory resolved that setup failure.

## Run the checks

1. Open QA. Create a neutral draft.
2. Import `scripts/fixtures/engine-native-actions.json` through the Actions importer.
   Its installation URL is `drafts://action?data=` plus percent-encoded file text.
3. Run Success. Check the returned Unicode text and the original window.
4. Run Cancelled and Error. Check that no following step changes the text.
5. Run Late. Type replacement text within eight seconds. After the reply arrives,
   check that the replacement remains and no window was added.
6. Run Shell. Check its Unicode output in the editor.
7. Check Execution History for each result.

The helper only opens callbacks with the QA scheme and callback host. It sends no
messages. Its control window can also deliver normal Draftly URLs explicitly to QA.
The helper checks the destination bundle identity and test-library setting. It
does not change the normal Draftly scheme registration. Close QA and remove only
the app copies and
library UUID created for this session. Keep the source and fixture for repetition.

## Automation checks

Use the helper control window to send normal `draftly://` URLs explicitly to QA.
Verify the field value before pressing Open in QA. The helper displays the actual
URL delivered. Check that QA is not running before each cold-launch case.

- Create: send neutral text and check the created note.
- Open: send that note UUID and check the selected row and text.
- Capture: send neutral text and check the separate Capture window. Pending
  capture text must remain across a quit and append the new text.
- Run: import `scripts/fixtures/engine-automation-actions.json`. Send action name
  and note UUID, plus x-success, x-cancel, and x-error URLs pointing to
  `draftly-engine-echo://received?status=...`. Confirm Run Action. The helper must
  show the final status and only the matching final parameters.

For App Intents, create a disposable shortcut in Shortcuts. Search for the exact
QA app name to separate it from other installed builds. Add Run Draft Action and
use the neutral action name and QA UUID. Test success, failure, and cancellation
separately. The recorded ad hoc build failed to communicate because the system
could not obtain its Team ID. Development signing fixed that setup failure.

For native Shortcut execution, create a separate disposable shortcut containing
only a Text action with output `Shortcut output café 🐼`. Name it
`Draftly QA Text — disposable`, then run QA Native Shortcut from Draftly.
The recorded UI execution of this shortcut worked. Both the app adapter and a
direct command-line invocation waited without completing. The app returned timeout
and retained the source text. Native Shortcut success remains pending.

Native callback timeout, entry-point timeout/busy/concurrency, speech, location,
Calendar, and Reminders still require their separate real checks. Deleting a
shortcut affects iCloud and other devices. Confirm deletion if normal recovery is
not available; retain the disposable fixtures while that confirmation is pending.

## Async prompt keyboard checks

Import `scripts/fixtures/engine-prompt-actions.json` with a `draftly://action?data=`
URL through the helper. Select a neutral QA draft. Run QA Async prompt keyboard.
Return must store the Unicode field text. Repeat with Escape and Cmd-period;
both must cancel and keep the source text. Run QA Async selection keyboard.
Type Second in its search field, then press Return. The note must read
`Selected: two`. Repeat and press Escape; the note must stay unchanged. Check
Execution History for the matching success and cancellation results. These checks
passed again on the fully refreshed development-signed QA build on 20 October
2026. The earlier a308158 attribution was invalid because the Debug library was
not refreshed. See docs/validation.md for the repeated acceptance. The alert
has no visible close control; other window-close paths still need acceptance.


## AppleScript process checks

Import scripts/fixtures/engine-applescript-actions.json into the isolated library.
Run success and check `AppleScript café 🐼`. Start cancelled, then type neutral
replacement text before eight seconds pass. The editor must remain available;
the runner must cancel and keep the typed text. Check that no helper child remains
and that the next action can run. Check Execution History. Use no external app
commands; these fixture scripts return neutral records only.

## HTML and export checks

Import scripts/fixtures/engine-html-file-actions.json into the isolated library.
Run QA HTML success. Native Continue/Cancel controls must be hidden. Press Send
neutral result. The editor must show `café 🐼`; the fixture also checks JSON null.
Run QA HTML cancelled and press its native Cancel. The source must stay unchanged.
Run QA File cancelled and press Escape in Save. The next insertion must not run.
Run QA File export and choose a new temporary folder. Check the actual saved bytes
against `Export café 🐼\nSecond line`. Check all four results in Execution History.
Remove only that neutral export and temporary folder after the check. These cases
passed in the fully refreshed 20 October 2026 QA build. No message fixture is
included; real sending needs an authorized recipient and content.

## Print, sharing, and arrangement checks

Import scripts/fixtures/engine-print-share-arrange-actions.json. Use a neutral
draft. Run QA Print cancelled and press Cancel in the native print sheet. Do not
print. Run QA Share cancelled and press Escape in the picker. Do not select a
recipient or service. Both runs must keep the draft and record Cancelled.

From the window action list, run QA Arrange result. Select Second 🐼, press Move
Up, then Done. The draft must contain Second 🐼 followed by First. Run QA Show
Arrange and Cancel; the draft must stay unchanged. The latter action can succeed
before the organizer closes. Compare history and content. Native timing, Undo,
navigation, window close, service completion, and output need separate acceptance.

Repeat QA Arrange result through an explicit draft UUID URL. Confirm the external
action, then Done. Read the saved target and check Success in history. The method
accepts text without a window editor. Window-bound UI methods need separate tests.
The updated QA Print cancelled preview must show one page for the short fixture.
Cancel and verify that Late print is absent. Do not send a printer job. These
cases passed in the fully refreshed 01:59 local QA run on 20 October 2026.

## Editor context and source close

From a cold QA launch, open the explicit neutral draft UUID. The target must be
selected without a row click. Run QA Show Arrange by URL while that draft is
visible. The panel must stay open after the action returns. Move a line, accept,
and use Cmd-Z in the real editor. Confirm the saved text and history.

Run QA Async prompt keyboard by URL and leave its prompt open. In the Window
menu, choose the source draft window and close it. Check that the prompt closes,
its action records Cancelled, and the source text stays unchanged. Do not count
the new-window behavior as accepted yet: an Untitled window appeared in the
20 October 2026 check. Diagnose that behavior separately. Do not start microphone
recording for these checks.

## Unknown imported steps

Import scripts/fixtures/engine-import-actions.json. In Engine import QA, inspect
QA Disabled future step and export it to a temporary folder. Check that the native
export retains rawPayload and isEnabled false. Cancel editing. Run both actions.
Disabled must succeed. Enabled must fail before Must not run appears in the draft.
Check the two history results. Remove the neutral export after checking it.

For source-close checks, use docs/manual-window-inventory.md. The independent
20 October 2026 control resolved the extra-window report for the tested case:
direct CUA observation reopened QA after it had zero windows. Observe only the
helper until an explicit reopen is part of the next test.

## Imported separators

Import scripts/fixtures/engine-separator-actions.json into the isolated library.
Select Engine separator QA. The list must show A, the B heading and horizontal
line, then C. B must not be an executable button. Its context menu must retain
Edit, Duplicate, and Delete. Edit B, increase Order, and save. It must move after C.
Search for Neutral section. The executable results must exclude B.

Check the editing bar, Actions menu, and executable picker separately. Export a
full backup and restore it into another temporary library. Check identity, order,
separator state, and unknown payload fields. Automatic recovery tests do not
replace this native recovery check. Direct engine execution of a separator has
no accepted reference behavior yet.

## Queue cancellation

Import scripts/fixtures/engine-queue-actions.json. Run QA Queue cancellation root
on a neutral draft with success, cancel, and error callbacks to the local helper.
Use draftly-engine-echo://received?case=queue&result=cancel as x-cancel, with
success and error as the other result values. The helper resets its in-memory
received count when Open is pressed. A late callback from another run can still
arrive; use distinct case values to identify it.

After confirming Run Action, check the saved text: Queue child completed write
followed by the fixture Unicode suffix. No ERROR sentinel may appear. The draft
must remain in Inbox because the cancelled child must not apply Archive. The
helper must show cancel and no root success parameter. Check history and observe
the received count again after inspecting the draft. The count describes only
that observation interval. Repeat error, timeout, and separate-draft variants
before accepting the full native queue contract.

The fixture also has QA Queue failure root and QA Queue timeout root. Failure
calls context.fail after saving its neutral text. Timeout saves its text in an
allowAsync step and omits script.complete. Wait for the production 120-second
deadline. Keep requests sequential and use a distinct case value in every
callback URL. The helper counts all received callbacks; it does not correlate
them with the active request. Confirm that the returned case matches the run.
Both variants must use x-error, keep the child text in Inbox, omit success
parameters, and skip both sentinels. Check the history status and error message.
During timeout, toggle a panel to check that MainActor stays responsive. Restore
its prior state. Do not change production deadlines to shorten native acceptance.

For the multi-draft cancellation root, create exactly one separate draft whose
content is Queue target neutral. Open the source draft before URL execution to
test the matching visible editor. The fixture validates the target before it
changes text. Source must keep Queue source retained; target must keep the
child's completed write in Inbox. The visible editor must finish on the target.
Inspect the source again to verify its stored content. Recreate the neutral
target content before repeating this fixture. With no matching visible editor,
the cancelled headless route saves the target but does not reveal it. These are
different entry conditions; record which one was tested.

## Inclusion cycle safety

Import scripts/fixtures/engine-cycle-actions.json. Record the source text, then
run QA Static cycle A. The A/B cycle must fail before the first script changes
text. Run QA Dynamic cycle root. Its earlier write must remain, but the selected
cyclic child's script and the root tail must not run. The draft must stay Inbox;
Archive is a success effect. Use unique local x-error callback case values and
check the error message, count, empty success parameters, and root history rows.

The reference documents inline inclusion and template names, but not a cycle
policy or numeric depth. Draftly rejects cycles as a safety policy. Its tested
50/51-action boundary is not a claim about the Drafts depth limit.

## CPU deadline

Import scripts/fixtures/engine-deadline-actions.json into the isolated library.
Run QA CPU deadline with a unique local x-error case. The script writes neutral
text before its infinite loop. The production synchronous deadline is ten
seconds. Toggle filters while the worker runs, then restore their state. After
timeout, check CPU completed write in Inbox, no tail sentinel, no discard
parameter, one observed error callback, and Error history with the timeout
message. Direct UI and App Intent execution need separate checks.

## Promise rejection

Import scripts/fixtures/engine-promise-actions.json. Run the discarded and
intrinsic async rejection actions with unique local success/error cases. Both
must report their rejection message without waiting for timeout. Earlier saved
text must remain in Inbox; no tail or Archive may run. The discard success
parameter must be absent. Run the caught rejection control. Its catch must save
Caught rejection completed and finish successfully. Check all three history
rows and callback results. Repeat broader entry-point variants separately.

## Concurrent URL requests

Import scripts/fixtures/engine-busy-actions.json. Open two distinct neutral
drafts in independent windows. Run QA Busy owner on the first draft. It saves
its text and waits thirty seconds. Before it finishes, run QA Busy rejected
request by URL on the other draft. Confirm both requests. Use distinct callback
case values. The second must return a busy error without changing its draft.
The first must finish successfully and keep Busy owner retained. Check both
window identities and history. The helper resets its count on each Open; after
the second Open it can receive both the busy result and the first run's success.
Identify results by case, not by the last callback alone.

## Selected identity and template inclusion

Import scripts/fixtures/engine-inclusion-actions.json. Rename QA Original child
to QA Included renamed child in the inspector and save. Do not duplicate it.
The fixed child UUID must stay unchanged. Run the root on a neutral draft. Its
first include retains the old name but selects the UUID. The second resolves
the new name from a template tag. Both must increment the same shared variable.
Check Included visits: 2 — café 🐼, Success history, and callback parameters
visits=2 and shared=retained. A fresh import restores the original child name
for another run; repeat the inspector rename before execution.


## Required initial configuration

Import `scripts/fixtures/engine-configuration-actions.json` in QA. Select neutral
text. Run the action, change Neutral label, then press Escape. The note and saved
configuration must stay unchanged. Run again, enter neutral Unicode text, and
choose Configure. The editor must show that value. Run again and restart QA;
neither run should ask for the confirmed field. Add a new required key and check
that only the new field appears. Check static and template-based included actions
separately. Text acceptance, Escape, restart reuse, and static/dynamic included cancellation
passed on 20 October 2026. New required fields and other control types remain
pending. See validation.md for the exact observed scope.


## Typed configuration and new required fields

Import `engine-configuration-typed-actions.json` in a fresh QA library. Disable
Neutral enabled. Enter not-a-number and choose Configure. The error must return
to the same values. Set the number to zero and accept. Check the editor JSON and
History Success. Export from the action editor. Use its stored action and step
identities, confirmed values, and confirmation metadata in a revised native-format
payload. Add a required string configuration step. Import the revision and run it.
Only the added field must appear. Confirm it and check that false and zero remain.
These native cases passed on 20 October 2026. The export is temporary. Do not
commit machine-specific exports or raw captures.


## Completion and step lifetime

Import `engine-completion-actions.json`. Run Completion epoch isolation on a
neutral note. The final script must succeed only after the current timer and
without the old timer. Run Duplicate completion failure. Expect one error callback
and the completed prior write in Inbox; no tail or Archive. Run Returned rejected
promise. Expect one error callback and unchanged source text. Use separate callback
case values and inspect History after each result. These URL cases passed on
20 October 2026. Other entry-point and timeout cases stay separately tracked.


## Current Shortcut fixture

Draftly QA Engine — disposable contains Run Draft Action from Draftly Engine QA.
Reuse this one fixture for remaining acceptance. The two older QA shortcuts were
deleted with approval. Do not remove this new fixture permanently without its
own approval. The final action setting is QA Busy owner with the neutral root
UUID. Native success, CPU timeout, and busy results passed on 20 October 2026.

For separate-target timeout, first import engine-queue-actions.json. Create exactly
one other Inbox note containing Queue timeout target neutral. Import
engine-queue-multiple-timeout-actions.json. Run that root on a different neutral
note through the Shortcut. Wait for the production120-second limit. Expect the
error, retained root/child text in Inbox, no tail or later queued action, and the
matching original window left on the child. This native case passed. Prepare a
new marker note for each repeat; the prior marker becomes the child output.


## Returned parameter keys

Use `scripts/fixtures/engine-callback-response-key-actions.json` with the current
QA helper. The `parameterKeys=true` option adds fixed neutral response keys,
including `__proto__`, `constructor`, and a quoted multiline value. Run the
action in the isolated QA app. Check the expected editor text and Success in
history. Preparing or importing the fixture does not prove acceptance.


## Delayed reply observation

The helper shows Reply pending while it waits. Replies opened counts successful
NSWorkspace URL opens. It does not mean Draftly accepted the response or that
an action succeeded. For QA Native late, cancel and run QA Caught rejection
before the eight-second reply. After the helper reports a successful open,
check the editor and history. The cancelled tail must not replace the new result.


For overlapping reply lifetimes, import engine-callback-overlap-actions.json.
Run Expired, cancel it, then run Fresh before the eight-second reply. The helper
uses optional replyValue to distinguish expired/fresh data; the normal default
remains unchanged. Expect two successful URL opens and only the fresh response
in the successful second action. Native open timing is not handler timing.
