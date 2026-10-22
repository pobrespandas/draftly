# Native sharing lifetime refactoring — 22 October 2026

## Reference and baseline

The clean reference is 7e8b478. The annotated reference tag is
pre-refactor-native-lifecycle-2026-10-22. No prior changes were discarded.
No build or test process was active at the initial check. The installed app
and the previously retired QA packages stayed unchanged.

The first complete baseline run failed in Core before editing. In
XMLRPCAsyncTests.actionInterruptionCancelsTransportAndStopsLaterSteps, the
cancelled=false case timed out before reaching the transport. It reported two
issues. A separate serial run passed all seven XMLRPCAsyncTests methods. A
separate app baseline passed all 765 methods. The local Debug build passed.
The baseline failure remains a prior concurrency risk. No timeout, retry rule
or unrelated production behavior was changed to hide it.

## Diagnosis and accepted scope

| Problem | Impact | Change | Risk and validation |
| --- | --- | --- | --- |
| SharingSession owns both continuation/timer and handed-off service retention. | Finishing the action can be confused with releasing a file still used by a service. | Extract a concrete private SharingActionWait. Keep service events, deadline decisions and resource ownership in SharingSession. | Callback order and object retention must stay unchanged. Characterize reentrant dismissal and overlapping resource lifetimes before extraction. |
| Tests cover late callbacks on one request but do not directly check a second pending picker. | A refactor could clean up another request or return its result. | Add a separate two-request characterization with distinct neutral files and drivers. | Keep all current test names and contract coverage. Use temporary files and injected drivers only. |

This stage covers sharing. It does not create a common native-operation base
class. Printing retains its own wait, cancellation flag and sheet cleanup rules.
Its existing tests run as integration guards. File preparation and system-picker
presentation retain their existing responsibilities and implementation.

## Implementation

SharingActionWait owns the continuation, timer and single final result. It
clears the continuation and cancels the timer before running presentation
cleanup. It resumes the caller after cleanup. It clears its cleanup closure
when it finishes. Cancellation still queues completion on MainActor.

SharingSession owns discovery, the original deadline checks, service events,
handed-off retention and disposal. A cancelled or timed-out action can leave
the service using its file. A late terminal service callback releases only
that session's file and driver. Result precedence, error text, default timeout,
owner-window selection and cleanup order stay unchanged.

The glossary now defines sharing handoff as a domain event. Technical lifetime
rules remain in the architecture document. There is no new protocol, public
API, stored field, migration, syntax rule or script change. Note, identities,
backups, library formats, preferences, Undo and editor content are unchanged.

## Automatic verification

Both new characterization methods passed against the original implementation:

- pickerDismissalCannotReplaceTheResultWithAReentrantCallback checks that a
  completion callback during picker dismissal cannot replace cancellation.
  Cleanup occurs once, before the caller receives the result.
- lateHandoffCleanupDoesNotFinishAnotherPendingRequest checks that a cancelled
  service can finish later without closing a second picker or removing its
  file. Duplicate late events do not repeat disposal.

The sharing characterization run passed 25 methods before extraction. After
extraction, the focused sharing and printing run passed 46 methods. The final
complete run passed 674 Core and 767 app methods. XML reports matched the
complete discovered inventory. All 68 Python tests passed. The final local
Debug build, structural matrix check and diff check passed.

No test was removed or renamed. The fixture clears its new dismissal callback
on detach. No automatic test opens, activates or moves a visible window, asks
for permissions, plays audio or uses personal data. Build and test commands ran
sequentially. Source files stayed frozen during complete test runs. Reports and
raw logs remain in /tmp/draftly-native-lifecycle-* and are not tracked.

## Native verification and limits

No new Computer Use session was needed for this private wait extraction.
SystemSharingDriver, presentation bindings and native-service calls did not
change. The previous owned-sharing native check remains historical evidence;
it is not a new native verification of this build. No QA app was installed or
launched, and the usual app was not replaced.

The strict engine check still reports six partial contracts and 18 diagnostics.
No compatibility status was upgraded. Native service outcomes, pending-permission
cancellation, unavailable model checks and reference-dependent checks remain
separate. The prior XML-RPC concurrent-baseline failure also remains recorded.

Resume cloning from docs/research/engine-native-checklist.md. This refactoring
does not close the Actions engine or Draftly cloning.
