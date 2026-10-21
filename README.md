# Draftly

Draftly is a native Mac app for quick text capture and actions. It uses SwiftUI,
AppKit, Core Data, CloudKit, and JavaScriptCore. It requires macOS 26 or later
and Xcode 26 or later with Swift 6.2 or later.

## Build and run

Build a local app without an Apple Developer profile:

```sh
scripts/build-app.sh --local
```

Open `.build/xcode/Build/Products/Debug/Draftly.app`. This build stores data on
this Mac. It shows that iCloud is not configured.

To enable iCloud:

1. Copy `Configuration/Signing.xcconfig.example` to
   `Configuration/Signing.xcconfig`.
2. Set your paid Apple Developer team ID. The main bundle ID is
   `com.pobrespandas.draftly`. Keep the existing
   `iCloud.com.andrestobelem.draftly` container.
3. Sign in to that team in Xcode. Open `Draftly.xcodeproj` and check Signing &
   Capabilities. Assign the existing container to the main App ID.
4. Run `scripts/build-app.sh --icloud`.
5. Open the app on two Macs with the same iCloud account. Use the checklist in
   [validation.md](docs/validation.md).

The configured paid team now provisions CloudKit and Push Notifications. Apple
reports its name as Andrés Tobelem, not pobrespandas. The signed build uses the
private Development container. The full sync matrix remains open.

`Signing.xcconfig` is ignored by Git. The project supports automatic signing.
CloudKit sync is eventual. Local saves do not prove a remote save.

Signed Debug builds use `.build/icloud/Build/Products/Debug/Draftly.app`.
Local builds keep their existing output. Set `DRAFTLY_BUILD_OUTPUT` to use an
isolated build directory. Set `DRAFTLY_PROVISIONING_PROFILE` to use an installed
manual profile when Xcode has no signed-in account. Run
`scripts/package-personal.sh` for a signed Release package for registered Macs. See
[icloud-distribution.md](docs/icloud-distribution.md) for profile limits,
installation, updates, and the current server test result. The main app is
installed at `~/Applications/Draftly.app`. Read
[bundle identity migration](docs/bundle-identity-2026-10-21.md) before changing
its identifier or restoring the previous package.

## Use Draftly

- Press **⌘N** for a new draft. Press **⌃⌥⌘N** to capture from another app.
- Empty drafts stay temporary until you type, add metadata, or run an action.
- Use the menu bar icon to open the independent Capture window. Pending capture
  text stays on this Mac when the window closes or the app restarts. Save it as
  a new draft, or append it to an existing draft.
- Quick Search opens a separate search window. Find in Draft List keeps the list
  search. Use Up, Down, Return, and Escape in Quick Search.
- Swipe a draft row to show Trash and Archive. Archived rows offer Inbox, and
  trashed rows offer Restore. Each row action affects only that row.
- Right-click a sidebar tag to rename it or remove it from the library. Removing
  a tag keeps the drafts. Saved workspace filters update with the tag.
- Type in the editor. Content saves after a 500 ms pause and before navigation.
- Enter tags separated by commas. Press Return to save a tag.
- Use the flag menu, Archive, and Trash to organize drafts. Trash keeps drafts.
- Use Command-click or Shift-click in the draft list for batch operations.
- Save a workspace to keep a draft view, search, tags, and sort order.
- Use the toolbar to show or hide filters, the draft list, and actions separately.
- Use the bottom editor bar for undo, redo, tasks, dates, and indentation. Select
  an action group from its left menu to run that group's actions.
- Click the eye button below the editor, or press **⌥⌘P**, to switch
  between editing and rendered Markdown in the center panel.
- Pin the current draft to keep it when returning to the app. Set New Draft After
  in Settings to change the idle timeout. The default timeout is five minutes.
- Use Float on Top in the main toolbar to keep the window above other windows.
- Use List Options to show previews, tags, and dates. Select one to three preview
  lines. These options stay saved on this Mac.
- Select an action group with the menu or bottom tabs. Use Search Actions to
  search all groups. Press **⇧⌘P** to open the command palette.
- Open Revision History to review or restore saved content.
- Use File → Export Full Backup to save the complete library. File → Import
  merges backups, Drafts JSON exports, text files, and action files. A selected
  set of files imports as one operation. If any file fails, that operation leaves
  the library unchanged.
- Open Actions → Import from Directory to load an action. Review it in the action
  editor before running it.
- Use Settings to change the editor font, size, line spacing, margins, maximum
  text width, typewriter scrolling, themes, and the main command shortcuts.
- Use Actions → Manage Actions and Workspaces to edit groups, action order, and
  saved workspaces. The action inspector controls visibility, confirmation,
  notifications, and tags and flags applied after success.

Each window has its own editor. Drafts, revisions, workspaces, actions, and action
groups are part of the library. File permissions stay on each Mac.

## Actions and automation

Actions contain ordered steps. The action editor can create, change, reorder,
duplicate, import, and export steps. It can set a group, a keyboard shortcut,
configuration values, and the draft's organization state after success.

The JavaScript bridge supports the five reference actions in
[compatibility.md](docs/compatibility.md). Scripts share one context across steps.
Unknown steps are preserved. An action with an enabled unknown step fails before any
step runs. Disabled unknown steps remain stored and do not run. Unsupported API calls produce an error in Execution History.

Native steps support the clipboard, sharing, file export, URLs, text insertion,
new drafts, Markdown preview, Shortcuts, AppleScript, Reminders, and Calendar.
AppleScript and Shortcuts run with the current user's permissions. Review
imported scripts before use. This personal app does not use App Sandbox.

Shortcuts can create, search, and open drafts, or run an action. URL examples:

```text
draftly://create?text=Hello
draftly://open?uuid=DRAFT-UUID
draftly://run?action=Copy&uuid=DRAFT-UUID
```

Percent-encode query values. External links that run actions require a prompt.
The app owns its `draftly` URL scheme. It does not register the Drafts scheme.

## Development

```sh
swift build
python3 scripts/run-swift-tests.py
python3 scripts/generate-project.py
```

The Swift package contains the reusable core, executable, and tests. The Xcode
project adds the app bundle, privacy descriptions, URL scheme, and entitlements.
Regenerate the project after adding or removing app source files.

The tests use in-memory stores or temporary folders. They do not access iCloud,
Reminders, Calendar, external apps, or the user's library. The five downloaded
action snapshots have source URLs and SHA-256 hashes in the fixture manifest.

The local library is in `~/Library/Application Support/Draftly`. The SQLite
store includes drafts, immutable content revisions, workspaces, actions, and logs.
Backups include action groups, syntax definitions, themes, and execution
history. They omit credentials and local file permissions. A backup restores both
copies when the same draft ID has different content or metadata. The copied
draft keeps its revisions and restored execution history. Conflicting execution
records also keep both variants. Older backups without execution history remain
supported. Repeating the same conflict import reuses an unchanged recovery made
by the current importer. Accessing that recovery does not create another copy.
Editing it preserves the edit and creates a separate recovery on the next import.
Random recovery identities from older versions are not matched by content alone.

The interface was checked against the installed Drafts Mac app. See the
[interface reference](docs/research/drafts-mac.md) for the controls used.

iPhone, iPad, Apple Watch, MCP, and email capture are outside this version.
Full Drafts API parity is still in progress. Action scripts can use MultiMarkdown and GitHub Markdown,
asynchronous completion, callback responses, and interactive HTML previews.
Markdown Settings control the default processor in previews and Action templates.
Native model sessions require an
available macOS model. See [compatibility.md](docs/compatibility.md) for limits.

## Repository map

| Location | Purpose |
| --- | --- |
| `Sources/Draftly` | App lifecycle, windows, controls, and native services |
| `Sources/DraftlyCore` | Library storage, models, templates, and Actions |
| `Tests/DraftlyTests` | Native editor, window, and app regressions |
| `Tests/DraftlyCoreTests` | Storage and scripting contracts; original action fixtures |
| `Configuration` | App metadata, entitlements, and signing examples |
| `Resources` | App icon |
| `Vendor` | Markdown parsers and their licenses |
| `scripts` | Build, packaging, audit, capture checks, and Python tests |
| `docs/research` | Frozen references, compatibility matrices, and acceptance evidence |

`DraftlyApp.swift` defines scenes. `AppController.swift` owns app coordination.
`AppDelegate.swift` owns the menu bar and global shortcut.
`ApplicationCommands.swift` defines app and window menus. `SettingsView.swift`
contains Settings pages. Preference access is separate from those views.

Start with [project status](docs/status.md) for implemented work and pending
acceptance. Use [architecture](docs/architecture.md) for component boundaries
and refactoring checks. Use [validation](docs/validation.md) for historical test evidence.
Use the [core audit](docs/research/core-actions-audit.md) and
[compatibility guide](docs/compatibility.md) for Actions limits. Use the
[iCloud guide](docs/icloud-distribution.md) and
[VM checklist](docs/utm-icloud-validation.md) for signed builds and sync checks.
The local handoff is `docs/claude-handoff.md`. It is not tracked by Git.

Run the Python checks with a Python environment that provides Pillow:

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Use [manual engine QA](docs/manual-engine-qa.md) for isolated native checks.
Refresh its existing bundle with `scripts/refresh-engine-qa.py`; copy all Debug
runtime files, not only the launcher. The script keeps the QA identity and checks
that its process is absent before replacement.

Keep acceptance summaries and frozen reference snapshots. Screenshots, session
evidence, raw logs, and generated caches stay local and ignored. They were removed
after the current cleanup. Generate new artifacts when a new check needs them.
