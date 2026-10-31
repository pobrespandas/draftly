# Use Draftly

Draftly is a Mac app for capturing text, developing ideas, and using actions
to copy, share, or export your writing. A draft is one text item in your
library. A workspace is a saved view of that library.

## Install and update

1. [Download Draftly](https://draftly.pobrespandas.com/). It requires macOS 26
   or later.
2. Open the DMG and drag Draftly to Applications.
3. Open Draftly from Applications.

The public app is signed and notarized. You do not need Xcode or an Apple
Developer membership. Draftly has one edition, with no Pro feature tier.
Use **Draftly → Check for Updates…** to check manually. The app asks before
installing an update.

## Capture a thought

Press **⌘N** to create a draft, then start typing. An empty draft stays temporary
until you type, add metadata, or run an action. Content saves after a short
pause and before you navigate away.

The menu bar icon opens Capture, a separate window for quick notes. You can
save its text as a new draft or append it to an existing draft. Pending Capture
text stays on this Mac when you close the window or restart the app.
The default shortcut for Capture from another app is **⌃⌥⌘N**.

Pin the current draft to keep it when you return to the app. **New Draft After**
in Settings controls when Draftly starts a new draft after an idle period.
The default is five minutes. Each window has its own editor.

## Find and organize drafts

Use tags, flags, Archive, and Trash to organize your library. Trash keeps drafts
until you empty it. Swipe a row for Archive or Trash; archived rows offer Inbox,
and trashed rows offer Restore. A row action affects only that draft.

Enter tags separated by commas and press Return to save a tag. Right-click a
sidebar tag to rename it or remove it. Removing a tag keeps the drafts and
updates saved workspace filters. Use Command-click or Shift-click to select
several drafts for a batch operation.

**Quick Search** opens a separate window. Use Up and Down to choose a result,
Return to open it, or Escape to cancel. **Find in Draft List** searches the
list itself. A workspace saves a view, search, tags, and sort order for later.

## Make the editor your own

Use the toolbar to show or hide filters, the draft list, and Actions separately.
Use **List Options** for previews, tags, and dates, with one to three preview
lines. These options stay saved on this Mac. **Float on Top** keeps the main
window above other windows.

Settings and Editor Settings control fonts, size, line spacing, margins,
maximum text width, typewriter scrolling, themes, and command shortcuts.
The bottom editor bar provides Undo, Redo, tasks, dates, and indentation.

Click the eye button below the editor, or press **⌥⌘P**, to switch between
editing and the integrated Markdown preview. Open Version History to review
or restore saved content.

## Run and organize actions

Select an action group with its menu or bottom tabs. **Search Actions** searches
all groups. The left menu on the bottom editor bar also selects an action
group. Press **⇧⌘P** to open the command palette.

Use **Actions → Import from Directory** to load an action. Review it in the
action editor before running it. **Actions → Manage Actions and Workspaces**
opens group, action order, and workspace management. The inspector controls
visibility, confirmation, notifications, and tags or flags applied after success.

## Back up or import your library

Use **File → Export Full Backup** to save your complete library.
**File → Import** accepts backups, Drafts JSON exports, text files, and action
files. A selected set of files imports as one operation. If one file fails,
that operation leaves the library unchanged.

Drafts, revisions, workspaces, actions, and action groups belong to the library.
File permissions stay on each Mac. See [library and backup behavior](development.md#library-and-backup-behavior)
for conflict handling and older backup formats.

## Scripts, Shortcuts, and URLs

Actions contain ordered steps. The action editor can create, change, reorder,
duplicate, import, and export steps. It can set a group, a keyboard shortcut,
configuration values, and the draft's organization state after success.

The JavaScript bridge supports the five reference actions in
[compatibility.md](compatibility.md). Scripts share one context across steps.
Unknown steps are preserved. An action with an enabled unknown step fails before any
step runs. Disabled unknown steps remain stored and do not run. Unsupported API calls produce an error in Execution History.

Native steps support the clipboard, sharing, file export, URLs, text insertion,
new drafts, Markdown preview, Shortcuts, AppleScript, Reminders, and Calendar.
AppleScript and Shortcuts run with the current user's permissions. Review
imported scripts before use. Draftly does not use App Sandbox.

Shortcuts can create, search, and open drafts, or run an action. URL examples:

```text
draftly://create?text=Hello
draftly://open?uuid=DRAFT-UUID
draftly://run?action=Copy&uuid=DRAFT-UUID
```

Percent-encode query values. External links that run actions require a prompt.
The app owns its `draftly` URL scheme. It does not register the Drafts scheme.

## What is still being checked?

Draftly is in development. It does not yet implement every Drafts scripting
contract or integration. The [compatibility guide](compatibility.md) separates
supported behavior from tests and native checks that are still pending.
Use [project progress](project-progress.md) for the current work list.
