# Pagination across CLI commands

Each CLI `call` closes its transport after the reply. Cursors previously belonged
to that short-lived session and were removed on closure. A following command
could not read the next page.

Read snapshots now belong to the authorized connection and grant. A new
transport can resume that same grant's cursor. Query and target binding,
fixed membership, current-value reads and both clock limits stay unchanged.
Other connections cannot use the cursor. Replacing the grant, invalidating the
connection or Stop Work ends access. Host restart also invalidates the cursor.

The local socket test reads two pages through separate one-shot CLI calls and
checks that hidden drafts stay absent. Service tests check reconnection under
the same grant and refusal after invalidation. Existing filter, scope, order,
expiry and clock-rollback tests remain required. This is not installed signed
client or post-update acceptance.
