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
