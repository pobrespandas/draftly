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
