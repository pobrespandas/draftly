# Local agent operation checkpoint

The agent service exposes operation queries and cancellation when its registry
is connected. An internal host option connects Action submission to the reviewed
executor. The option is off by default.
Normal application startup still needs a verified lock adapter. Published
builds keep agent access disabled.

## Implemented internal path

- Reviewed Action execution binds the request to its connection, library and draft.
- Script and step guards check the current grant and approved Action definitions.
- Native share effects require an interactive request and a single-use review.
- Settings can approve or deny a pending review. Stop Work invalidates reviews
  and cancels running operations.
- The operation registry tracks ownership, cancellation, timestamps and results.
- Repeated request IDs return their operation. Changed requests fail. Removing
  a result does not permit a replay within that host lifetime.
- Host admission requires an explicit editor window and draft write permissions.
  Missing or unknown windows fail before execution.
- Host tests execute a Unicode edit and query its terminal result. A share test
  reaches human review, then Stop Work cancels execution before approval. The
  next edit does not run, and the stopped connection cannot query results.
- Every execution authorization checks that the selected editor is still in the
  live window registry. Approval cannot restore access to a removed editor.
- Action requests apply `timeoutSeconds` to the operation, including time spent
  waiting for review. The default is 120 seconds. Expiry requests cancellation;
  the operation stays active until execution returns. Confirmed cancellation
  produces a timeout report. An uncertain effect remains `outcome_unknown`.
- Native effect records contain the operation kind, outcome and scoped resource
  IDs. They do not contain the native payload. Recording starts after approval
  and before handoff. A successful share records completion; a cancelled share
  records failure. Invalid responses or interrupted handoffs remain unknown.
  Earlier records remain visible when a later effect has an uncertain outcome.

## Installed isolated check — 2 November 2026

A Developer ID QA build at commit `1f86a1e` ran from Applications with the
signed embedded helper. The app used a new temporary library with iCloud off.
Access started off. Native Settings approved pairing after code comparison.
The helper authenticated through Keychain and read the open editor through CLI.

CLI submitted the default Share Action for the neutral text `QA local café 🐼`.
The operation waited for human review. The review showed the exact text, Action
version, draft version and target window. Allow once opened the native macOS
share selector. Cancelling the selector returned a terminal cancelled report
with `Share cancelled`. No share destination was selected.

A separate MCP stdio probe initialized the installed helper, listed tools, read
the draft and retrieved the cancelled operation. This did not submit an Action
through MCP or prove support for a named external client. Revocation made a new
CLI request fail with `permission_denied`. Stop Work left access off. QA then
quit, and its app bundle was retained outside Applications.

This build used the QA lock adapter. It does not prove screen-lock handling,
normal startup, notarization, restart recovery or production acceptance.

## Remaining integration

The private operation journal can reserve a request identity and save a validated
snapshot through atomic file replacement. Its tests cover reopening, retained
effects, grant changes and corrupt files. Request parameters are represented by
a fingerprint. The journal is not connected to the operation registry yet, so
the running host still has no restart recovery or durable replay protection.

1. Complete result coverage and records for non-native effects. Native effect
   records are connected. Snapshot encoding checks the execution result schema.
2. Verify operation queries and cancellation through installed CLI and MCP.
   The service checks connection ownership and original resource scope.
3. Verify the optional host execution path with native effects and installed
   clients before enabling it at application startup. Advertise only handlers
   that are connected and verified.
4. Persist request history and uncertain outcomes before enabling replay recovery.
5. Verify the installed signed app and helper through CLI and MCP, including
   pairing, scope isolation, cancellation, revocation and restart.

The current registry is bounded and in memory. It does not provide recovery
or replay protection across a restart. A failed response does not prove that
an effect did not occur. Do not replay an uncertain effect automatically.
