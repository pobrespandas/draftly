# Operation retention review

The current journal has one limit of 128 records per library. This is not a
concurrency limit. Completed and uncertain records use the same capacity as
running work. The file survives host restart. A new connection does not receive
new capacity. `removeCompleted` removes a live entry but keeps its request
reservation and durable record.

`journalCapacityIsGlobalAndSurvivesConnectionReplacement` characterizes this
failure. It fills the journal, opens a fresh registry with only a different
connection, and checks that new work returns `busy` before any effect. The first
request identity remains recoverable. This test records the existing failure
mode. It does not accept it as publication behavior.

## Required behavior

Separate concurrent-work admission, cached results and durable request identity.
A completed result must not consume a permanent execution slot. Evicting result
content must not evict the fact that a request already submitted an effect.
An uncertain outcome must remain distinguishable from a request never accepted.
A restart, transport reconnect or grant replacement must not bypass this rule.

Define when a request identity becomes permanently inadmissible before removing
its replay protection. Wall-clock expiry alone is insufficient: the clock can
move backward. A paused connection can resume and is not retired. A missing
credential read can be a transient storage failure and does not prove retirement.

The connection registry commits revocation and changes its grant identifier before
it removes credentials. Failed revocation can block only the current process.
Any future retirement cleanup must use committed authority state, not just that
process-local block. Cleanup must not race with in-flight result persistence.
The treatment of uncertain effects as retained activity also needs an explicit
policy; denying old authority alone does not provide an audit record.

## Implementation checks

- More than 128 sequential completed jobs must work under one valid grant.
- A full active-work limit must reject before an effect and recover capacity
  after confirmed completion or cancellation.
- Retrying an evicted result must return its identity or an explicit unavailable
  result. It must never start work again.
- Retain uncertain-effect protection across restart, storage failure and clock
  rollback. Test committed revocation separately from pause and failed writes.
- Keep file size and memory bounds. Storage exhaustion must fail before submission.
- Migrate the existing journal atomically. Preserve old reservations if migration
  fails. Do not reset or delete the file to gain capacity.

No retention algorithm is accepted yet. Raising the numeric limit or deleting
oldest records does not meet these requirements. Publication remains gated on
implementation and tests of the selected policy.

Validation: all 18 journal tests passed. The log is
`/tmp/draftly-journal-capacity-characterization.log`. No production behavior changed.
