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

## Remaining integration

1. Complete operation result coverage and recorded effects. Snapshot encoding
   already checks the existing execution result schema.
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
