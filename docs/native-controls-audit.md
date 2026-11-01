# Native control audit

Reviewed the current macOS source on 1 November 2026. This inventory describes
Draftly's implementation. It does not establish Drafts' private implementation.
SwiftUI is also a native Apple framework. A custom interaction or the wrong
AppKit configuration can differ from the reference in either framework.

## Main surfaces

| Surface | Current implementation | Remaining review |
| --- | --- | --- |
| Main toolbar | `ReferenceToolbar.swift`: `NSToolbar`, native items and groups, tracking separators | Some symbols use custom vector drawing. Native ownership does not prove matching images or configuration. |
| Main panels | `LibrarySplitView.swift`: `NSSplitViewController` with hosting controllers | Width restoration is custom. Explicit animation was removed after user feedback. |
| Settings tabs | `SettingsView.swift`: `NSTabViewController` in toolbar mode | Page contents use SwiftUI. Existing tab work remains separate from this audit. |
| Editor | `EditorView.swift`: AppKit text view and scroll view | Syntax, paragraph layout, completions, and current-line rendering are customized. Keep the text system; compare each behavior. |
| Draft list | `DraftListPanel.swift`: `NSTableView`, native row actions, hosted row content | Row typography and layout are custom. |
| Search fields | `VisualControls.swift`: `NSSearchField`; quick search uses a native input bridge | Tag-filter search uses a separate SwiftUI field. |
| Menus | `PanelMenu` uses `NSButton` and `NSMenu` | Symbol dimensions and popup placement are set manually. Some control rows mix these buttons with SwiftUI plain buttons. |
| Action group bar | `ActionGroupButton.swift`: AppKit buttons with hosted symbol content | Hover bezel configuration required correction. Press opacity is still customized. Two symbols are compositions. |
| Editor action bar | `EditorActionBar.swift`: moved from SwiftUI plain buttons to AppKit accessory-bar buttons | Compare hover and pressed states against the supplied screenshots. |
| Action list | `NativeActionTable.swift`: `NSTableView` with hosted row content | Native selection, arrow keys, double click, Return, and context menus. Row icons and separators still use SwiftUI. Search section headings and accessibility secondary actions need more comparison. |
| Folder selector | `VisualControls.swift`: `FolderControl` uses buttons, capsules, and drawn separators | Priority: imitates a segmented control. Compare with `NSSegmentedControl` before replacing it. |
| Editor footer and panel utilities | `EditorFooter.swift`, panel headers: mostly SwiftUI plain buttons | Priority: same interaction family as the reported hover mismatch. |
| Filter sidebar | `DraftFiltersPanel.swift`: custom rows, chips, backgrounds, and buttons | Selection and focus are manually assembled. Review keyboard and pointer behavior. |
| Tag entry | Native `NSTokenField` while editing; custom SwiftUI capsules while idle | Two implementations of one control can disagree on appearance, hit areas, focus, and accessibility. |
| HTML preview | `WKWebView` with a custom SwiftUI presentation container | The reference uses a separate Preview window. Native web rendering does not resolve that presentation difference. |
| Prompts and file dialogs | `NativePromptAdapter`, file commands: AppKit fields, tables, alerts, open/save/print panels | Custom composition still needs contract-specific checks. Do not replace working native controls wholesale. |

## Order of work

1. Match pointer and pressed feedback in the two action bars. Use the supplied
   reference screenshots, not the assumption that any native bezel is correct.
2. Review footer and panel-header buttons as one interaction family.
3. Review the folder selector and action list against their native counterparts.
4. Review tag display and filter selection, including focus and keyboard input.
5. Review the separate Preview window and remaining Settings controls.

This is a source inventory of the main surfaces and supporting controls. It is
not a completed interaction audit of every sheet, dialog, or editor setting.
