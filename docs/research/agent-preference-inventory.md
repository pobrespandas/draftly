# Agent preference source inventory

Status: application metadata catalog implemented, 1 November 2026.
`AgentPreferenceCatalog` declares 86 reviewed fields from the owners below.
It performs no storage or native calls. No agent preference handler is enabled.
The contract registry accepts explicit trusted fields. It never discovers fields
from UserDefaults or from request data. Test fields are fixtures, not evidence
that each setting has an application handler.

## Existing owners

| Family | Existing owner | Binding requirement |
| --- | --- | --- |
| Appearance and launch window/menu | `ApplicationPreferences.swift`, `SettingsView.swift` | Reuse appearance and navigation enums. Keep launch-window and menu defaults. |
| Login | `LoginItemPreferences.swift` | Use its service adapter, not a stored boolean. Installation status and approval can block it. |
| Spotlight | `SpotlightPreferences.swift` | Keep its indexing coordinator and error state. Indexing exposes draft data outside the app and needs human approval. |
| Capture lifetime | `SettingsView.swift`, capture consumers | Keep the existing supported intervals and capture persistence. Do not clear capture to change a preference. |
| Advanced Find and Touch Bar | `GeneralPreferences`, `WindowPreferences.swift` | Preserve the existing window consumers. A preference write does not prove hardware acceptance. |
| Global editor defaults | `EditorSettingsView.swift`, `LibraryView.swift`, `EditorPreferences.swift` | Consolidate shared defaults before adding the application registry. Do not add another independent table. |
| Syntax fonts | `EditorSyntaxFontPreferences.swift` | Use its named/monospace font and size setters. Preserve inherited globals and unknown JSON fields. |
| Syntax layout | `EditorSyntaxLayoutPreferences.swift` | Use the existing finite nonnegative values and reset rules. Keep margins, width and paragraph behavior separate from a view's slider range. |
| Syntax text input | `EditorTextInputPreferences.swift` | Keep option defaults. Autocorrection and Writing Tools can inherit system behavior; nil does not mean false. |
| Syntax display | `EditorSyntaxDisplayPreferences.swift` | Preserve legacy insertion-point fallback and per-syntax paragraph numbers. |
| Indentation | `EditorIndentationPreferences.swift` | Reuse the existing style enum and malformed-store behavior. |
| Syntax features | `SyntaxFeaturePreferences`, `SettingsOptionEditing.syntaxFeature` | Resolve an authorized definition and its declared feature before editing. Preserve other features and syntax records. |
| Markdown | `MarkdownPreferences.swift`, `MarkdownSettingsView.swift`, `SettingsOptionEditing.markdownOption` | Derive names and defaults from the existing option arrays. Preserve disabled and unknown values. |
| HTML | `HTMLPreferences.swift`, `HTMLSettingsView.swift` | Keep consumer normalization and link/image/emphasis behavior. Do not expose an encoded options blob as a general storage writer. |
| Shortcuts | `CommandShortcuts`, `GlobalShortcuts`, `SettingsOptionEditing.command` | Reuse editable names, bindings and conflict checks. Distinguish clearing a binding from removing its override. Preserve imported data. |
| Local list defaults | `DraftListDefaults`, `WindowPreferences.swift` | Keep local values separate from an applied Workspace. Do not mutate Workspace definitions. |
| Default Workspace | `WorkspaceDefaults` in `WorkspaceAPI.swift` | Resolve and scope-check the referenced identity. A default selection does not apply a Workspace to a window. |
| Theme selection | `EditorThemePreferences`, `InstalledThemeCommands` | Use the dedicated theme selection contracts and separate slot/definition versions. Do not expose bookmark bytes. |
| Folder bookmarks | `BookmarkPreferences`, `BookmarkSettingsView.swift` | Preserve names and the native folder picker. Add a stable local identity adapter before serving UUID-based requests. |

The catalog tests freeze the field IDs and compare defaults with these owners.
These metadata checks do not prove live effects, persistence or native acceptance.
Use the existing setters for JSON field edits. A reset removes only the selected
known override. It does not delete an entire preference domain or discard unknown
fields. Local application and window state stay separate from shared definitions.

## Excluded from the preference interface

Do not register credentials, Keychain values, agent grants, pairing state,
connection tokens, bookmark data, signing configuration, CloudKit identifiers,
private histories or arbitrary storage keys. Keep privacy grants in protected
system UI. iCloud remains outside this Settings change.

Raw storage names in this document identify code owners. An agent cannot use a
name from this document unless the application explicitly registers a public
field and its typed context. Permission to write a setting does not authorize
an external file, system registration or a connection-grant change.

## Remaining application work

1. Connect the reviewed application field catalog to the scoped schema handler.
   `AgentPreferenceCatalogTests` freezes 86 fields, including syntax contexts,
   inherited and system defaults, command contexts and protected native changes.
2. Keep the shared default constants used by Settings and editor consumers.
   The characterization tests preserve values and legacy Boolean conversion.
3. Add typed getters and mutations with temporary domains and injected native
   adapters. Test malformed data, storage failure, unknown fields, per-field
   reset, inheritance and conflicts. Do not read personal preferences in tests.
4. Connect grant checks, version tokens, receipts and protected approval. Check
   reference scope before returning metadata or changing configuration.
5. Verify live effects, editor state and Undo in isolated QA. No preference or
   native permission changed during this source audit.
