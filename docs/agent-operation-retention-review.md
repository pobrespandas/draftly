# Operation retention review

The journal now separates durable request identity from the bounded live result
cache. Individual records replace the global 128-record admission limit. This
removes the permanent request-count failure without dropping replay protection.
See the [storage decision](adr/0006-agent-indexed-operation-journal.md).
Implementation and local validation do not establish installed acceptance.

## Original failure

The previous array allowed only 128 records per library. Completed and uncertain
records used the same capacity as running work. A restart or a new connection
did not receive new capacity. A characterization test reproduced that behavior.
Its corrected test now verifies reservation and recovery of 260 identities.
Raising the array limit or deleting oldest records was not a valid fix.

## Current storage

Each connection/request pair has one bounded private record. An operation index
maps its identifier to that record. Lookups read the requested files and the
bounded legacy recovery copy; they never enumerate the history directory.
The existing global lock serializes reservations and snapshot changes. The
index commits first. Work starts only after the request record also completes
its file and directory durability checks. A partial index alone is not accepted
work and fails closed on result lookup. Failed reservation never launches work.

The old array remains unchanged in `operations-legacy.json`. Migration publishes
a format marker at `operations.json` after the copy is durable. Older apps reject
that marker, so they cannot ignore new requests and repeat effects. Migration
can resume after failure. Legacy records preserve their operation, request and
grant identity. Snapshot changes use individual records and retain the legacy
copy. Corruption is rejected without repair or automatic replay.

Disk use grows with accepted requests. Each file and each read has a byte bound;
the full history has no fixed byte budget. Storage failures must stop reservation
before submission. After submission, uncertain effects retain their identity.
No automatic age cutoff or deletion policy is implemented. A paused connection,
a clock change or a transient credential failure cannot remove protection.

## Live cache

Admission evicts only the oldest terminal durable entries when the cache is full.
It removes cached request mappings, not journal records. Requests check durable
identity before admission limits. Active work keeps its slot until terminal
completion. Without a journal, the existing in-memory identity bound still
applies. Private native results can become explicitly unavailable after eviction,
just as after restart. No effect runs to rebuild them.

## Regression evidence

- A capacity-one registry completes 140 sequential requests and retries each
  without another execution. It covers Actions and typed value operations.
- Active work blocks new admission, then releases capacity after cancellation
  reaches terminal state. Its retry cannot execute again.
- 260 request reservations survive reopening with their original identifiers.
  A different connection can reserve additional work.
- A full legacy array retains all 128 uncertain reservations after migration.
  New reservations work. The original recovery copy remains byte-for-byte intact.
- Failed migration keeps the original array. A retry preserves its identities.
- An orphan index fails closed. An obstructed reservation cannot launch work;
  removing the obstruction permits one execution and subsequent recovery.
- Native-result tests inspect the individual record for private input and output.

Before the live-cache fix, both parameter cases failed with `busy`; see
`/tmp/draftly-live-retention-red.log`. The earlier source passed 2,655 strict
Swift tests and native Debug build. Current indexed-storage validation is recorded below. Installed migration, disk-exhaustion fault injection
and signed update acceptance remain publication checks.

## Final local validation

The strict runner verified 1 consumer, 193 contract, 824 Core and 1,640 app tests
(2,658 total). After the final missing-marker recovery guard and its test,
39 focused tests in three suites passed. The final native Debug build passed.
The full run preceded that last guard; full CI for the final source remains open.
Logs: `/tmp/draftly-indexed-journal-full.log`,
`/tmp/draftly-indexed-journal-recovery-final.log` and
`/tmp/draftly-indexed-journal-final-build.log`.
No installed library or public release was changed.
