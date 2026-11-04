# Direct editor opening validation

`editor.open` now connects both contract forms to app-owned window selection.
An existing window requires its explicit identifier and `expectedWindowVersion`.
A new window requires `newWindow: true`. Neither form chooses an implicit active
window. The host advertises this operation only when editor membership, the
app-owned scene factory and operation control are connected.

The request needs `ui.present` and draft reading. Existing-window replacement
also requires scope for that window and its current draft. Saving pending source
text needs `drafts.write`. Source content and editor state are checked again
before submission. The native flush retains conflict and version rules. A cut
after saving prevents target loading and yields an uncertain outcome.

New-window opening uses the authorized scene adapter. It begins with an empty
editor, rechecks authority around loading, and returns the actual registered
window identity. It does not flush another active editor. The returned identifier
does not broaden the connection grant: a grant for only the draft cannot then
read the new window. Unexpected pending editors and late/cancelled scenes keep
the adapter's protection. Focus defaults to false and is passed to native
selection. Explicit existing-window focus also works on the current draft
without saving its pending text.

The operation journal binds request identity and the resolved affected resources.
Retries return the original result or error without creating another scene,
loading another draft, saving again or moving focus. A recovered version token
describes the original result. Read the current editor before a new change.
Transport closure does not revoke accepted work. Expiry, revocation, cancellation
and host invalidation still end authority.

## Local evidence

The focused run passed 174 tests in six suites. It checks both opening forms,
clean and pending source editors, default and explicit focus requests, shared
MCP tool discovery, source/window/target scope denial, stale versions, changed
editors, revocation, transport closure and journal recovery. Creation tests
stage a real scene request, then cancel, expire or invalidate it before a late
window attaches. No late scene loads the target. A separate publication test
ends authority after a source save and verifies no replacement or replay.
Tests use isolated libraries and native window objects without presenting the
SwiftUI app. They do not accept visible focus or installed scene behavior.

Strict complete Swift validation verified 1 consumer, 193 contract, 824 Core and
1,660 app tests (2,678 total). The native Debug build passed. Logs:
`/tmp/draftly-editor-open-final-focused.log`,
`/tmp/draftly-editor-open-full.log` and `/tmp/draftly-editor-open-build.log`.
Full CI of this source, signed installed opening/navigation/focus, cancellation
while displaying UI, and post-update client sessions remain open. No installed
library or public release changed.

Source coverage is 108 connected/conditional names out of 137; 29 lack a direct
handler. This does not establish complete operations or published support.

## Previous CI allocation result

[41873396266](https://github.com/pobrespandas/draftly/actions/runs/41873396266)
for adapter source `43aade3` passed plan, tooling and matrix. The native job had
no runner or executed steps. GitHub reported unavailable hosted runner capacity
for macOS arm64. The aggregate check failed, as required. Keep native CI pending
until a runner executes the selected checks successfully.
