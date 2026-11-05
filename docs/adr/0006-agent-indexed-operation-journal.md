# Keep durable operation identity in individual records

The journal must accept sequential work beyond 128 requests without dropping
retry protection. A single bounded array cannot provide both behaviors. Keep
one bounded private record per connection and request. Use a bounded operation
index to find that record by operation identifier. Keep the bounded live cache
separate from durable identity.

The existing global journal lock serializes reservation and result writes. New
work starts only after both index and request-record writes complete their file
and directory durability checks. The index is written first. A crash before the
request record commits leaves an orphan index, not accepted work. Looking up that
index fails closed. Retrying an unsubmitted request can create a new reservation.
A committed request record always keeps its original operation identity.

Preserve the old array as `operations-legacy.json`. Publish a version marker at
`operations.json` only after that copy is durable. An old app cannot decode the
marker as its array and must reject access. Never delete or reset the legacy
copy. Legacy lookup uses the saved identity; later snapshots use an individual
record with the same identity. Migration failure leaves the original array or
the committed format marker and recovery copy. Retrying migration is safe.

Each read and write has a byte limit. Lookups do not enumerate the directory or
load the full history. Retain request identities and uncertain outcomes without
an automatic age cutoff. Disk use grows with accepted work. Storage exhaustion
must reject reservation before submission; a failure after submission produces
an uncertain outcome and never triggers automatic replay. This decision does
not claim a fixed total disk budget or automatic history cleanup.
