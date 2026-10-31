# Develop Draftly

This guide is for people who want to build or change the app. To install the
released app, use the [download page](https://draftly.pobrespandas.com/).

Draftly uses SwiftUI and AppKit for the Mac interface, Core Data and CloudKit
for storage, and JavaScriptCore for action scripts.

## Requirements

- macOS 26 or later.
- Xcode 26 or later, with Swift 6.2 or later, for local development.
- Public release builds require the macOS 27 SDK and Swift 6.4 or later.
  See [release operations](releasing.md).

## Build and run locally

Build a local app without an Apple Developer profile:

```sh
scripts/build-app.sh --local
```

Open `.build/xcode/Build/Products/Debug/Draftly.app`. This build stores data on
this Mac. It shows that iCloud is not configured.

### Signed iCloud development builds

These steps are for maintainers with access to Draftly's Apple Developer team
and existing container. A person who downloads Draftly does not need Xcode or
an Apple Developer membership. For a local build without that team access,
use `--local` above.

To build with the existing iCloud identity:

1. Copy `Configuration/Signing.xcconfig.example` to
   `Configuration/Signing.xcconfig`.
2. Set the configured Apple Developer team ID, `NM92LU2KKV`. The main bundle ID is
   `com.pobrespandas.draftly`. Keep the existing
   `iCloud.com.andrestobelem.draftly` container.
3. Sign in to that team in Xcode. Open `Draftly.xcodeproj` and check Signing &
   Capabilities. Assign the existing container to the main App ID.
4. Run `scripts/build-app.sh --icloud`.
5. Open the app on two Macs with the same iCloud account. Follow the
   [VM checklist](utm-icloud-validation.md).

The configured paid team now provisions CloudKit and Push Notifications. Apple
reports its name as Andrés Tobelem, not pobrespandas. Debug and personal builds use the
private Development environment. Public Developer ID packages use Production
in the same container. Keep their acceptance separate; the full sync matrix
remains open.

`Signing.xcconfig` is ignored by Git. The project supports automatic signing.
CloudKit sync is eventual. Local saves do not prove a remote save.

Signed Debug builds use `.build/icloud/Build/Products/Debug/Draftly.app`.
Local builds keep their existing output. Set `DRAFTLY_BUILD_OUTPUT` to use an
isolated build directory. Set `DRAFTLY_PROVISIONING_PROFILE` to use an installed
manual profile when Xcode has no signed-in account. Run
`scripts/package-personal.sh` for a signed Release package for registered Macs. See
[icloud-distribution.md](icloud-distribution.md) for profile limits,
installation, updates, and dated server test results. Public release operations
are in [the release guide](releasing.md). Read
[bundle identity migration](bundle-identity-2026-10-21.md) before changing
its identifier or restoring the previous package.

## Change code and run tests

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

### Library and backup behavior

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

### Reference and scope

The interface was checked against the installed Drafts Mac app. See the
[interface reference](research/drafts-mac.md) for the controls used.

iPhone, iPad, Apple Watch, MCP, and email capture are outside this version.
Full Drafts API parity is still in progress. Action scripts can use MultiMarkdown and GitHub Markdown,
asynchronous completion, callback responses, and interactive HTML previews.
Markdown Settings control the default processor in previews and Action templates.
Native model sessions require an
available macOS model. See [compatibility.md](compatibility.md) for limits.

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

Start with [project progress](project-progress.md) for implemented work and pending
acceptance. Use [architecture](architecture.md) for component boundaries
and refactoring checks. Use [validation](validation.md) for historical test evidence.
Use the [core audit](research/core-actions-audit.md) and
[compatibility guide](compatibility.md) for Actions limits. Use the
[iCloud guide](icloud-distribution.md) and
[VM checklist](utm-icloud-validation.md) for signed builds and sync checks.
The local handoff is `claude-handoff.md` in this directory. It is not tracked by Git.

See [Testing Draftly](testing.md#run-the-checks) for the Python environment,
Swift result checks, and website tests.

Use [manual engine QA](manual-engine-qa.md) for isolated native checks.
Refresh its existing bundle with `scripts/refresh-engine-qa.py`; copy all Debug
runtime files, not only the launcher. The script keeps the QA identity and checks
that its process is absent before replacement.

Keep acceptance summaries and frozen reference snapshots. Raw QA screenshots, session evidence, logs, and generated caches stay local
and ignored. The requested website product screenshot is a tracked asset.
See [repository maintenance](repository-maintenance.md) for that distinction.
