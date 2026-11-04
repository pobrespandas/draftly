# Direct theme selection validation

`themes.select` and `themes.selectBuiltIn` now connect to the app's theme reference
rules. They require appearance management, preference storage and the shared
operation registry. They do not require an editor or destructive mutation mode.

Use `themes.selection` for the requested appearance's current `versionToken` as
`expectedVersion`. Installed selection also requires the target's `themes.get`
version as `expectedThemeVersion`. Installed resources must be in scope. File
themes require `files.read` and valid saved file access. A changed file or theme
fails validation before the preference write. Built-in selection uses public
catalog names and does not require access to an installed theme.

Native and agent selection share the same preparation of references. It keeps
the other appearance, legacy selection behavior and unknown fields. Corrupt
reference data remains unchanged. The agent commits the reference data and local
revision in one compared preference-domain write. The existing storage owner now
has a final validation boundary before replacement. The selector rechecks theme,
selection and authority at that boundary. Native UI selection keeps its existing
write behavior and uses the shared preparation.

Accepted work belongs to its connection rather than its submitting transport.
The journal records its original result. A retry or reopened service does not
select again, increase the revision again, or replace a later manual selection.
A write failure or authority loss after replacement returns an uncertain outcome
without automatic rollback or replay. Selection uses the durable registry rather
than a new bounded host-lifetime receipt map.

## Local evidence

The focused 177 tests in five suites passed. They include installed and built-in
selection in both appearance slots, structured sibling and unknown-field
preservation, corrupt preferences, stale versions, resource denial, cancellation,
revocation, current file reads and file permission denial. Fault tests apply a
preference write and then fail or invalidate authority; retries do not write again.
A 140-selection test verifies live-capacity release and recovery of every retry
identity without another revision increase. Existing native theme preference and
storage tests remain green.

Strict complete Swift validation verified 1 consumer, 193 contract, 824 Core and
1,667 app tests (2,685 total). The native Debug build passed. Logs:
`/tmp/draftly-theme-selection-expanded.log`,
`/tmp/draftly-theme-selection-full.log` and `/tmp/draftly-theme-selection-build.log`.

Full CI of this source, signed installed appearance changes and process-restart
persistence remain open. A selected reference does not prove rendered pixels or
replace Workspace appearance rules. Reload, replacement, installation and theme
deletion still lack direct handlers. No installed library or public release changed.
Source coverage is 110 connected/conditional names of 137, with 27 missing handlers.

The preceding `editor.open` source `cee030e` passed all selected CI jobs in
[41877332833](https://github.com/pobrespandas/draftly/actions/runs/41877332833),
including native build/tests and tooling. This does not accept the later selector.

File-theme tokens now also bind the saved permission. Same-content retargeting
invalidates `expectedThemeVersion` before selection can write preferences. The
permission token tests cover this behavior; see
[installation evidence](agent-theme-installation-review.md).
