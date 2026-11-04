# Direct editor preview validation

`editor.preview` now uses the app-owned window model and the durable operation
registry. It requires `ui.present` and draft reading for both the target window
and its current draft. The service advertises it only when editor membership and
operation control are connected. It does not require destructive mutations or
reviewed native Actions to be enabled.

The request sets an explicit visible state. It never toggles blindly. The
existing UI command still flushes before presentation. The agent path uses the
same presentation setter without flushing pending edits, saving a scratch draft,
or changing the draft's text, selection, dirty state or Undo history. The preview
uses the existing Markdown view, which disables JavaScript and supplies a
`default-src 'none'` content policy. It does not use an action's custom HTML.

A running action, custom preview or marked-text composition blocks the request.
The accepted operation binds the editor generation. A draft switch, edit or
closed window before submission fails without presentation. Accepted work can
outlive its submitting transport; expiry, revocation and host invalidation still
end its authority. Authority is checked before and after the presentation.
Interruption after submission returns an uncertain outcome without a result.

The journal records request identity and the small presentation result. A retry,
including after reopening the service, reports that outcome. It does not set the
view again, even when the person has since changed the visible state. This is a
receipt of the original operation, not a live query of the current preview.

## Local evidence

The focused run passed 49 tests in four suites. It includes preview show/hide,
actual native Undo/Redo, pending text and version preservation, result recovery,
transport closure, target and capability denial, composition, action conflict,
changed/closed editors, revocation and authority loss during presentation.
The availability test requires both host components. An out-of-scope window
returns `not_found`, as the existing privacy policy requires.

The normal native Debug build passed. Logs:
`/tmp/draftly-editor-preview-verified.log` and
`/tmp/draftly-editor-preview-build.log`.
Strict complete Swift validation verified 1 consumer, 193 contract, 824 Core
and 1,645 app tests (2,663 total). The log is
`/tmp/draftly-editor-preview-full.log`. Full CI of this source remains open. Signed installed
presentation, real focus behavior and post-update client acceptance remain open.
Editor opening and navigation still have no connected direct handlers.
