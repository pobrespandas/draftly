# Bounded operation waiting

Date: 4 November 2026. Installed acceptance is pending.

`operations.wait` uses the asynchronous service path in the socket broker and
Chat Console. It observes an operation owned by the same connection. It returns
on a terminal state, human attention or an observer deadline of 1–30 seconds.
The deadline and observer cancellation do not cancel or replay the work.
The registry limits active observers to 16. It checks session and live grant
authority while waiting and before returning data. The client response budget
allows five seconds of margin above a maximum-length wait.

## Focal validation

The final focal run passed 199 tests in seven suites. Registry tests cover
completion without replay, pending review, observer timeout, cancellation,
capacity, revocation, grant replacement, scope changes, lock and clock rollback.
Service tests cover concurrent status requests, another connection and revocation
before delivery. The transport budget test checks valid and invalid wait input.

An earlier completion test depended on a real one-second deadline under suite
load. It now uses a fixed injected clock and a yielding sleep. Separate tests
still check elapsed observer deadlines. The corrected focal run passed.

Two project-generator tests passed. The native Debug build passed with the
existing package identity flag `-package-name chat_console` and signing disabled.
A build without that flag failed to resolve package-access contract types.
This change does not claim to repair that build configuration.

## Complete validation

The first strict run stopped during the existing
`RunDraftActionIntentTests.shellInterruptionWaitsForProcessCleanupBeforeIntentReturns`
test. The app process exited with code 1 before it emitted results XML. No
completed strict report exists for that run. The isolated 14-test Intent suite
then passed, including timeout and cancellation. The cause of the interruption
is not established. The full recheck passed strict inventory verification: 1 consumer, 183 contract,
822 Core and 1,616 app tests (2,622 total). This does not explain the first exit.
Do not treat the first run as a pass.

Logs are retained under `/tmp/draftly-operation-wait-*`. Full CI, installed wait
behavior and post-update client acceptance remain separate gates.
