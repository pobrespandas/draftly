# Direct editor navigation validation

`editor.navigate` uses the current window's visible list, sort and filters. It
selects the previous or next draft through the app-owned selection path. The
request needs the current editor version, `ui.present`, draft reading, and scope
for the window, source draft and destination draft. It does not skip a hidden
destination to find another authorized draft. Out-of-scope destinations return
`not_found` before saving or changing selection.

Read access can navigate a clean editor. Saving pending text also requires
`drafts.write`. The native flush keeps its conflict checks and version creation.
At a list boundary, the native no-op keeps pending text without saving it, so
write permission is not required. Conflicting pending windows, composition,
active Actions, custom previews and an active Arrange session block navigation.

The editor token now binds the stored content bytes as well as the current
projection, syntax, selection and dirty state. It does not bind unrelated stored
metadata. This prevents navigation from overwriting concurrently stored text;
restoring the same content and syntax can restore the same editor state. A list
or editor change before execution fails without selecting a new destination.

The app resolves additional affected drafts. The registry validates and records
those resources alongside the request's window target. The client cannot supply
these extra resources as a replacement for its target or grant. Authority is
checked before flush, before recording destination access, before loading, and
after selection. If authority ends after saving, selection stops and the result
is uncertain. A retry never saves or navigates again.

Accepted work can survive closure of the submitting CLI transport. The durable
journal retains its result after reopening the service. That result describes
the original navigation. Its version token is not a promise about the editor's
current state after further UI changes or a host restart.

## Local evidence

The focused run passed 172 tests in five suites. Coverage includes both directions,
clean read access, authorized pending saves and versions, implicit resource scope,
transport closure, restart recovery, composition, conflicts, stored content changes,
closed windows, list changes, revocation and host invalidation. A storage
publication test ends authority after the source save and verifies that the
destination is neither accessed nor loaded. Its retry remains uncertain.
The final full run also includes the added read-only dirty/out-of-scope case.

The shared editor tests remain green. The token excludes modification and access
dates. State-based retries still work after content and syntax are restored;
concurrently different stored content invalidates the old editor token.

Logs: `/tmp/draftly-editor-navigation-final-focused.log` and
`/tmp/draftly-editor-navigation-final-build.log`. Strict complete validation verified 1 consumer,
193 contract, 824 Core and 1,649 app tests (2,667 total). The log is
`/tmp/draftly-editor-navigation-full.log`. The final native Debug build passed.
Full CI of this source remains open. Installed navigation and native focus, cross-device storage
conflicts, and post-update client sessions remain open. Later direct opening validation is recorded in
[its own report](agent-editor-opening-acceptance.md).
