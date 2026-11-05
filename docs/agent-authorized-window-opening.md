# Authorized new-window opening

The app now has a separate authorized new-window adapter. It uses the real scene
request registry and returns the actual registered window model. This is a
foundation checkpoint for `editor.open`. Its later service integration is
recorded in [opening validation](agent-editor-opening-acceptance.md). At this
checkpoint, coverage was 107 connected/conditional names with 30 missing handlers.

The caller supplies live authorization. The adapter checks it before target
lookup, before scene loading, around native selection, and before returning.
The scene must begin with an empty editor. It cannot flush a restored or changed
editor outside the request. The adapter passes the requested focus flag to native selection. Visible focus
is not yet accepted. Normal
user and Action opening still use the existing path and default focus behavior.

A pending request can close only its unchanged empty editor or the unchanged
requested draft. Pending text, composition, Actions, custom previews or Arrange
prevent automatic closure. Cancellation retains a retired scene identity. A
late scene cannot load the requested draft or close a changed editor. Completed
windows return to normal app ownership; later registration does not revalidate
an expired agent grant. The completion callback is released after selection.

Tests use native NSWindow objects without displaying them. They verify both
focus-token modes, authorization before lookup, denial before loading and after
recording access, unchanged drafts and versions, unexpected pending editors,
late registration after cancellation, and completed-window ownership. They do
not prove visible focus or installed SwiftUI scene behavior.

## Integration status

The later opening implementation connects this factory through the app-owned
editor registry. It supports explicit-window and new-window requests with scope,
version checks and the durable operation journal. Installed scene behavior,
visible focus, expiry/Stop Work while displaying UI, and signed-update client
sessions remain open. Read the opening report for that later evidence.

The initial 19 opening tests and native Debug build passed. The final lookup
ordering check adds one test. Strict final validation verified 1 consumer,
193 contract, 824 Core and 1,654 app tests (2,672 total). The final native Debug
build passed. Logs: `/tmp/draftly-authorized-window-final-full.log` and
`/tmp/draftly-authorized-window-final-build.log`. Full CI of this source remains
open. Logs are under `/tmp/draftly-authorized-window-*`. No installed
library or public release was changed.

## CI allocation gate

The previous navigation source `0f9c51f` did not complete CI. In
[41869494074](https://github.com/pobrespandas/draftly/actions/runs/41869494074),
plan and matrix passed. Native and tooling jobs had no runner or executed steps.
GitHub annotations report that hosted runners were not acquired and macOS arm64
capacity was constrained. The aggregate check correctly failed because selected
jobs did not pass. This is not native build or test evidence. Keep the normal
checks enabled and validate the next source on a new CI run.
