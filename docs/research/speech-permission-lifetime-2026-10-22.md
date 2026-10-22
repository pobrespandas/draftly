# Speech permission and cleanup — 22 October 2026

## Base and scope

The base is 488d851 on the engine acceptance case branch. Main remains c82ae79.
Both worktrees were clean and no build or test process was active. The focused
baseline passed 41 methods. Tests use injected drivers, fake time and neutral text.
They do not open windows, request permissions, capture audio or use personal data.

## Cancellation reason regression

NativeTranscriptionRequest awaited each phase through TranscriptionPhase. A
phase reply schedules completion on MainActor. Cancellation also schedules its
cleanup on MainActor. If an expired reply is queued first, the old finish method
can report timeout even though the request task is already cancelled.

cancellationWinsWhenAnExpiredReplyIsQueuedBeforeCleanup reproduces the fault in
speech authorization, file selection and recognition. All three cases returned
timeout before the fix. A fake clock reaches the exact deadline; the reply is
queued and the request is cancelled before the actor can process completion.
There is no sleep or increased timeout in this regression test.

The phase now records cancellation synchronously under an NSLock. finish checks
that state after phase cleanup and before deadline/result selection. It resumes
once with CancellationError when cancellation is already recorded. The phase
still releases its picker/recognition cleanup exactly once. Late replies retain
the continuation guard. Existing timeout and cancellation defaults are unchanged.
This follows the existing dictation cancellation pattern. No shared framework,
public API or new capability was added.

The [Swift cancellation handler source](https://github.com/swiftlang/swift/blob/main/stdlib/public/Concurrency/TaskCancellation.swift)
was consulted through find-docs/Context7. The handler can run concurrently with
the operation. Queuing actor cleanup alone does not record the cancellation at
that time. This source supports the locking boundary; the regression establishes
the actual Draftly fault.

After the fix, all 42 focused methods passed. The local Debug build passed.
This is a functional correction, separate from additional coverage below.
It does not accept a real OS permission outcome or native speech timeout.

## Acceptance limits

SPEECH-DENY/CANCEL/LATE and MIC-DENY/CANCEL/LATE remain native obligations.
A fake grant or denial proves the adapter branch, not the system dialog.
The current dictation adapter still needs its native success/cancel/capture
cleanup session. A quiet neutral phrase and a separate QA app are required.
No private conversation will be recorded. No privacy database will be reset.

Further controlled coverage and complete validation are recorded in follow-up
updates. No new native acceptance is claimed by the focused correction.

## Additional controlled coverage

Six further methods close specific automatic gaps without removing old cases:

| Test | Observation | Native case still pending |
| --- | --- | --- |
| NativeDictationRequestTests.requestedPermissionRefusalCleansWithoutCaptureAndAllowsRecovery | Requested speech denial/restriction and microphone refusal cause one cleanup, no capture/panel, and permit a fresh Unicode result | MIC-DENY; actual speech/microphone denial |
| NativeDictationRequestTests.staleAuthorizationCannotAdvanceOrFinishTheNextSession | Speech/microphone grants and denials from a cancelled request cannot start capture or complete the next waiting request | MIC-CANCEL/LATE and pending speech grant |
| NativeDictationRequestTests.sameTurnRecordingCancellationRejectsTranscriptAndDoneBeforeCleanup | Cancel followed immediately by update/Done produces CancellationError, no new displayed text and one resource cleanup | DICTATE-02 with actual microphone |
| NativeTranscriptionRequestTests.requestedPermissionRefusalInvalidatesWithoutPickerAndAllowsRecovery | Requested denial/restriction stops before configuration/picker, invalidates once and allows a new request | SPEECH-DENY with actual system dialog |
| NativeTranscriptionRequestTests.staleRepliesCannotChangeOrFinishTheNextTranscription | Old authorization, file and recognition replies cannot advance or finish a new recognition request | SPEECH-LATE and native late recognition |
| NativeTranscriptionRequestTests.actionCancellationRetainsCompletedTextStopsLaterStepsAndRecovers | The real worker/runner with an injected speech host returns cancelled, drops success parameters, retains saved Unicode text, skips later steps/Archive, and runs recovery successfully | Actual UI/URL/Intent speech dispatch and permissions |

The action test covers cancellation while authorization or recognition waits.
It uses an explicit editor-operation hook to meet the existing active-editor
precondition. The first fixture attempt omitted that hook and ended before the
speech driver. Adding the hook corrected the test setup; no production guard
changed. The host throws if the synchronous route runs. Driver event streams
finish when execution ends, so an early execution failure cannot leave a stage
wait hanging. No visible editor window is required.

Fixture counters now track each transcription invalidation and displayed
transcript. They check actual driver effects rather than only returned text.
These are fixture changes, not changes to native capture implementation.

## Final automatic verification

Focused 53 methods passed across seven suites, including range Undo and script
Undo. Complete Core 679 / app 792 passed with matching XML/discovery inventory.
Python 80, local Debug compilation, structural matrix 0 and diff checks passed.
The strict engine gate still has six partial contracts and 18 diagnostics. No
status, native result, timeout or scheduling rule was promoted or relaxed.
The earlier Core startup/XML-RPC timing risks did not recur in this run.

Source/tests stayed fixed during the complete final run. Swift tests and builds
did not overlap. The correction and the additional coverage use separate commits.
Outputs use /tmp/draftly-speech-lifetime-* and are not versioned. No screenshot
or raw log is added. No original action fixture or public API changed.

## Prepared manual probes and current blocks

scripts/fixtures/engine-speech-permission-actions.json has two neutral actions
with distinct IDs: QA Dictation permission lifecycle and QA Transcription
permission lifecycle. They save a neutral marker before requesting speech.
Task cancellation, denial or timeout must retain that marker, omit the tail and
Archive, and return the corresponding final report. A user Cancel returns empty
text from these APIs; the probe explicitly calls context.cancel for that result.
A normal nonempty result has a separate success branch. This probe behavior is
not a change to the API's empty-string contract.

Import only into an isolated QA app and select a neutral draft. Do not run on
personal text. Dictation needs a quiet session with only the agreed neutral
phrase. Transcription needs neutral synthetic audio. Record actual OS permission
state first. Do not reset privacy databases or infer pending authorization from
an already granted state. Protected permission gestures need the user.

The user's availability for a quiet dictation session was requested. No native
speech session was started in this stage and no microphone was activated. The
manual probes were prepared, not executed. Their explicit identities pass the
existing Python collision check. No native permission, capture cleanup or
production 120-second recognition timeout is newly accepted. Existing positive
speech/transcription evidence remains in the dated validation records.


## Native audio callback fault found during acceptance

A separate manual session used the existing Engine QA identity, signed with
team NM92LU2KKV. It used only the neutral speech fixture and a new temporary
library (7764586B-7C73-438E-8DA6-5773EEE836EB). CloudKit and Services were disabled.
The user reported granting speech recognition permission. The protected system
prompt was not readable through Computer Use. No privacy database was reset.

The first attempts retained the fixture marker in Inbox. Reopening QA confirmed
that text. Two subsequent runs exited before Computer Use could observe the
Dictation panel. The system log for process 11059 at 19:47:28 reported audio
engine start followed by a libdispatch assertion: the block expected the main
queue. Audio therefore started briefly; absence of a visible panel does not
prove that capture never started. No recognized text was observed or accepted.
The old 18:56 launch-constraint crash report belongs to a different attempt and
must not be used as the cause of this exit.

SystemDictationDriver.startRecording created its audio tap closure inside a
MainActor class. The installed macOS 27 SDK declares AVAudioNodeTapBlock
NS_SWIFT_NONSENDABLE and explicitly permits invocation outside the main thread.
This allows inherited actor isolation that the audio callback cannot satisfy.
The [Swift migration guide](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/IncrementalAdoption.md)
describes the same missing-annotation inference and the explicit Sendable remedy.

DictationCallback.audioTap now creates an explicitly Sendable callback outside
the driver actor. It only appends the supplied buffer to its recognition request.
The driver still creates and owns its engine, request and panel on MainActor.
Recognition updates still return to MainActor. No timeout, permission rule,
selection rule or public API changed. This functional fix is separate from the
previous cancellation correction and coverage commit.

DictationCallbackTests.audioTapCreatedOnMainActorAcceptsSyntheticAudioOffActor
creates the production callback on MainActor and invokes it from a detached task
with 32 silent synthetic frames. It starts no engine, recognition task or device.
Both callback tests pass. Full Core679/app793 results match XML/discovery; Python80,
local Debug build, structural matrix0 and diff checks pass. The strict engine
gate still has six partial contracts and18 diagnostics. No deadline or retry rule
changed. Test/build outputs remain in /tmp/draftly-audio-tap-* outside Git.

The corrected QA package passed deep/strict signature validation. SHA256:
- Draftly: 727b905cf2b1d1de3218153cf9736d030b1a21b088770e0de55062020df564d0
- Draftly.debug.dylib: 137cc06947e7b4aefd7f012e3c6ed1e21da31c4e2271b322b1c73342524543cc

Computer Use then observed the Dictation panel with Listening, Cancel and Done.
The user was asked to say only the agreed neutral phrase and choose Done.
No phrase result arrived during this wait. Computer Use selected Cancel at 19:52.
The panel closed. The draft retained only Retained dictation café 🐼 in Inbox.
No completion tail appeared. Execution History showed one Cancelled row with
Neutral user cancellation. This is the fixture's explicit empty-result branch,
not task cancellation, permission denial or timeout. The process log confirms
engine stop and input Stopped at 19:52:13, before the normal QA quit.
The exact QA process is absent. Its exact LaunchServices record was removed.
The package and neutral library remain at their temporary paths for recovery.

This accepts the native user-Cancel subcase from the action palette and capture
stop for this package. Recognition/Done, Undo, URL/Intent speech entry points,
permission denial, pending grant cancellation and production timeout stay open.
The user-reported grant alone does not accept those outcomes. The usual app
remains unchanged. No raw log or screenshot is tracked.


## Neutral phrase follow-up

The user requested another attempt and then reported completion. Computer Use
observed the editor text `Prueba neutral de Daf Fitly`, with no Dictation panel.
QA remained responsive. The recognizer changed the product name; do not record
an exact transcript match. The process21673 log shows engine and input stop at
20:17:18. This verifies native recognition, insertion and capture stop for the
corrected QA package. The user operated the recording completion control.

Execution History showed Success at19:59 and20:00 and Cancelled at19:52. The
current draft was in Inbox without the fixture completion tail, modified20:17.
Those older Success rows do not establish a final action result for the20:17
capture. Do not infer tail/Archive acceptance or a new UI/URL/Intent engine case
from this observation. The exact entry used for the latest capture was not
observed. Undo/Redo, denied or pending permissions, production timeout and full
speech action completion remain separate checks. No new permission was granted
by the agent. No source changed and no tests or builds ran during this session.
QA remains open and idle with its neutral text visible; the usual app is unchanged.


## Controlled interruption follow-up

The baseline at18392a4 passed44 methods across the dictation, transcription,
callback and injected-host suites. No build or test was active. QA was idle and
quit normally before automatic tests. This stage changes tests and records only;
production callbacks, permission policies and deadlines remain unchanged.

NativeDictationRequestTests.interruptedActionRetainsWritesSkipsSuccessAndRecovers
runs the real worker and ActionRunner with an injected dictation driver. Its five
cases cancel during speech permission, microphone permission and recording, or
return requested speech/microphone denial. They verify the final error/cancel
reason, empty success parameters, one cleanup/host finish, retained Unicode
writes, no later step or Archive, and one run record. Old grants, refusals,
recognition and Done callbacks cannot change the following successful action.
No driver opens a real panel or device.

The existing transcription actionCancellationRetainsCompletedTextStopsLaterStepsAndRecovers
keeps its method name and now also covers task cancellation during file selection.
Authorization and recognition variants remain. Assertions include picker and
recognition cleanup counts. It retains earlier writes and ignores the late file
selection after cancellation before the successful recovery action.

alreadyCancelledTaskDoesNotTouchPermissionOrCaptureDriver and
alreadyCancelledTaskDoesNotTouchPermissionOrFileDriver cancel before the request
starts. They verify no prompt, capture, file selection or driver cleanup begins.
These cases differ from cancellation of an already started operation.

The first new test compile triggered a Swift compiler assertion on an immediate
invocation of a require macro result. Binding the required callback before
invoking it removed that compiler failure. No app rule, test deadline or retry
changed. The corrected focused47 passed. Full Core679/app796 matched the complete
XML/discovery inventory. Python80 and local Debug build passed. No Swift build
and test overlapped. Structural/strict results and native follow-up are below.

These injected cases do not accept system permission denial, pending OS prompts,
real task cancellation in the recorder or a native timeout. Existing QA grants
cannot establish those outcomes. Do not reset TCC to manufacture a pending grant.


Structural matrix validation reports0 errors. The strict engine gate still
reports six partial contracts and18 diagnostics. Supporting references were
added for the new runner and pre-cancelled request tests. Status and native
acceptance were not promoted. Outputs use /tmp/draftly-speech-followup-* and are
not versioned. Automatic tests ended before the native session below.


## Native transcription selector cancellation and recovery

A separate Computer Use session used the same corrected, signed Engine QA
package and neutral library. No source changed. QA used its existing speech
grant. The agent did not change permissions or reset the privacy database.

From the action palette, QA Transcription permission lifecycle saved its neutral
marker and opened Open. Computer Use chose Cancel without opening a file. The
panel closed, Inbox retained only Retained transcription café 🐼, and no tail or
Archive ran. History showed one Cancelled row at20:24 with Neutral user cancellation.
The fixture explicitly maps the API empty result to context.cancel. This is
user cancellation, not cancellation of the action task or pending permission.

A following palette execution selected only
/tmp/DraftlySpeechFollowupNeutral/neutral.aiff through Go to Folder. The system
say command generated this Spanish synthetic audio from neutral text; it was
never played or recorded through a microphone. The resulting editor text was
Prueba neutral de transcripción este texto es una prueba de la aplicación,
followed by Completed neutral tail. The draft appeared in Archive. History added
one Success at20:24 after the Cancelled row, with no duplicate final result.
This proves recovery on a fresh native transcription action after selector Cancel.
It does not prove a real recognition timeout or cancellation during recognition.

Opening Actions after recognition had already completed showed Cancel Running
Action disabled. No task cancellation was performed. The menu observation became
stale after Escape. Its exposed accessibility Cancel action restored the main
window without quitting, relaunching or changing the application. This is a
Computer Use observation issue, not evidence of app unresponsiveness.

A further new neutral draft opened the selector at approximately20:26:14. No
file was selected. This separate check uses the unchanged production wait limit.
At20:28 the panel closed without input. Inbox retained the marker, with no tail
or Archive. History showed one Error with The action operation timed out before
it completed. This is an end-to-end production wait timeout during file selection.
It does not isolate the host deadline from the selector phase deadline, and does
not accept TRANSCRIBE-01 recognition timeout.

A fresh palette execution then opened a new selector and used the same neutral
AIFF. It completed, archived the draft and added one Success after the Error.
After normal QA quit, a read-only check of the closed neutral library confirmed
these four durable run records and no duplicate result for the observed attempts:

| Outcome | Run ID | Neutral note ID |
| --- | --- | --- |
| Picker user Cancel | E2A99067-BE49-4D2E-AF2B-CAE44C2BDC0B | 33CE5302-DE8B-48C1-A036-BD0698A5C1DA |
| Recovery after Cancel | 1A20C33E-126E-4908-BFBE-077276007733 | 33CE5302-DE8B-48C1-A036-BD0698A5C1DA |
| Timeout while selecting | 627FA1EC-4A28-4C1F-AE89-C3E33D9DAA0E | 44F0DB3D-C624-4512-BBC2-A73C8D99D9BB |
| Recovery after timeout | EE7F000E-1FC3-4598-8DE1-5941EC9B67C5 | 44F0DB3D-C624-4512-BBC2-A73C8D99D9BB |

These are persistent log IDs, not observed ActionExecutionSession IDs. Both
notes contain the synthetic transcript and completion tail and remain archived
after recovery. UI observations before recovery establish retained Inbox markers
for Cancel and timeout; the final database state cannot substitute for those
intermediate observations. The selector was absent after both interruptions.
The exact QA process is absent after normal quit. Its exact LaunchServices entry
was removed. The package, neutral library and synthetic audio remain recoverable
at their temporary paths. The usual app, personal library and clipboard were
not changed. No screenshot or raw log is added to Git.

Still pending: actual speech/microphone denial or restriction; cancellation of a
pending OS grant and a late grant; native action-task cancellation during live
capture or recognition; native late recognition; production recognition timeout;
URL/Intent speech dispatch; native dictation Undo/Redo. Existing grants block a
new pending-grant outcome without a user-managed permission session. They are
not exclusions. The current tests use injected outcomes for those branches.
No new production defect was reproduced in this follow-up. No callback isolation
rule was changed from an unobserved risk. The engine gate remains open.


## Live action-task cancellation follow-up

The next dictation attempt opened Dictation on a new neutral draft. The user
reported using Cancel or the panel close control. The exact gesture was not
observed. The latest persisted dictation log6D3D62BF-F63E-499E-BA7F-3BF6FC6C39C9
instead records Success at20:33. Its note160DBC12-22AB-4621-89BC-CD1C667B993C
has the completion tail and Archive. This is not accepted cancellation evidence.
It requires a controlled reproduction before diagnosing a close-control defect.
Do not reinterpret this outcome as Cancelled or claim the user used another
control. No private transcript from this attempt is copied into the record.
QA quit normally for a read-only check; no production code changed.

The agent then ran the transcription fixture from the action palette on a new
neutral draft. The selected file was long-neutral.aiff in the existing temporary
neutral folder. The system say command generated it locally from30 repetitions
of the same neutral Spanish phrase, with no playback or microphone recording.
After Open closed and recognition was active, Actions showed Cancel Running
Action enabled and all runnable actions disabled. Computer Use selected Cancel
Running Action directly. The resulting main window retained only the fixture
marker in Inbox. The completion tail and Archive did not run. History added one
Cancelled at20:35 with an empty message, distinct from the fixture's explicit
Neutral user cancellation branch.

A fresh palette run selected the short neutral.aiff and succeeded. History
added one Success after Cancelled. A read-only check after normal QA quit confirms:

| Outcome | Persistent run ID | Neutral note ID |
| --- | --- | --- |
| Task cancelled during recognition | EF837AA5-F2C7-493B-8D61-3E6DDE0A6662 | 26F53FFE-C943-4F25-A017-A859210E20C1 |
| Fresh recovery Success | 0D515DBC-3B5A-47C3-A383-F1005C683D5A | 26F53FFE-C943-4F25-A017-A859210E20C1 |

The final note is archived and has the short transcript plus completion tail.
The UI observation before recovery establishes retention after cancellation.
No late text or duplicate result was observed during recovery. This is not proof
that a real late recognition callback arrived. The SDK exposed no independent
cancellation acknowledgement in the inspected system log. Resource-release
internals therefore retain the controlled-driver evidence; do not claim an
independent native task-deallocation measurement. The exact QA process is absent
and its exact LaunchServices record was removed. Neutral data remain recoverable.

This accepts task-cancel dispatch, retained writes and recovery for transcription
from the UI. It does not accept URL/Intent dispatch, pending-grant cancellation,
recognition timeout or live dictation task cancellation. Dictation still needs
a quiet session with the observed Cancel Running Action command. Existing
Core679/app796/Python80 validation still applies: source and tests did not change.
Only documentation and structural matrix validation ran in this follow-up.
