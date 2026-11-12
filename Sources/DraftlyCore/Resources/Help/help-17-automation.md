# Scripts, Shortcuts, and URLs

An action can contain native steps and JavaScript steps. Scripts in the same action share a context. Review imported scripts and the apps or services they use before running them.

Native steps include clipboard operations, sharing, file export, URLs, text insertion, new drafts, previews, Shortcuts, AppleScript, Calendar, and Reminders. Availability depends on the step, configuration, and macOS permissions. Unsupported integrations are not made available just because an imported script names them.

Draftly does not use App Sandbox. Automation can act with the current user's permissions. Review external effects before approving them.

## Shortcuts
Draftly's Shortcuts integration can create, search, and open drafts and run an action. Check the chosen draft and action in the shortcut before running it.

## URL examples
```text
draftly://create?text=Hello
draftly://open?uuid=DRAFT-UUID
draftly://run?action=Copy&uuid=DRAFT-UUID
```
Percent-encode query values. Replace DRAFT-UUID with the actual draft identifier. External links that run actions require a prompt. Draftly owns the draftly URL scheme; it does not register the Drafts scheme.

Drafts scripting compatibility is not complete. Use [the compatibility reference](https://github.com/pobrespandas/draftly/blob/main/docs/compatibility.md) for technical limits.
