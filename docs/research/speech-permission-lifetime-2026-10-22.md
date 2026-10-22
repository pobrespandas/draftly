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
