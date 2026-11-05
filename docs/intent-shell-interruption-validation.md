# Intent Shell interruption fixture

Date: 4 November 2026.

The complete local run for action-group removal failed in the existing Intent
Shell interruption test. The start marker was absent after five seconds.
The failure did not prove that process cleanup had started. An earlier full run
had also exited in this test before it produced results XML.

The old fixture used a real two-second host deadline before it observed the
Shell start. The fixture now uses the existing injected host clock and sleep.
It advances that clock only after the real Shell has written its parent PID,
child PID and temporary script path. Cancellation still interrupts the real
Intent task. Both cases still check that the parent and child are gone, the
temporary directory is removed, prior writes remain and following effects do
not run. A later Intent must still succeed.

The five-second process-start bound remains. If it expires, the fixture waits
for cancellation cleanup and reports the action outcome. It does not leave an
unobserved task to affect later tests. This change removes the deadline race;
it does not establish the cause of every earlier process exit.

The focused serial Intent suite passed all 14 tests. The real timeout and
cancellation cases passed together in 1.262 seconds. The final combined source passed strict inventory verification: 1 consumer,
184 contract, 824 Core and 1,621 app tests (2,630 total). Both interruption
cases passed in that complete run. The native Debug build also passed.
Production clocks and timeouts did not change. CI remains a separate gate.
