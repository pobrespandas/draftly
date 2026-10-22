Draftly is a native Mac app for quick text capture and actions. Its interface is a quiet macOS frame around the text: system fonts, system colors, SF Symbols, hairlines, and one accent. Color appears in small, meaningful doses: flags, action symbols, and message severity. Build anything for Draftly so that it looks like it ships with macOS.

## Content fundamentals

- Write in US English, sentence case for messages and Title Case for menu commands and tooltips: "Pin Current Draft", "Version History", "Import Action Group…".
- Address the person as "you" in help and settings. Name the object, then the result: "Copied 230 characters to the clipboard."
- Use short sentences and active voice. Use the same term for the same concept: a **draft** (never "note" in UI text), an **action**, an **action group**, a **workspace**, a **tag**, a **flag**.
- Use an ellipsis character (…) on commands that open a dialog: "Add File Syntax…".
- Name shortcuts with Mac symbols in parentheses: "Preview Markdown (⌥⌘P)". Write ⌘N, ⌃⌥⌘N, not Cmd-N.
- Empty states are a plain fact without a period: "No action selected".
- Do not use emoji in interface text. Drafts can contain emoji; the footer statistics count them.

## Visual foundations

### Color

- Use macOS semantic colors. Set text in `label` on `canvas` or `window`; set secondary text in `label-secondary`. `label-secondary` measures about 3.9:1 on a light `canvas`: use it for meta text, symbols, and headings at 13px or more, not for long copy.
- Use `accent` for selection and for toggles that are on. Put `on-accent` text and symbols on `accent` fills.
- Use the `system-*` colors only with a fixed meaning: flag color, action tint, banner severity, or editor syntax. Never use them as decoration.
- `system-yellow`, `system-orange`, and `system-green` are below 3:1 on a light `canvas`. Always pair them with a symbol or shape; never set text in them.
- In Light and Dark, success and error differ by hue only. The banner symbol (checkmark vs xmark) carries the meaning. Use the High contrast theme where that is not enough.
- `icon-gradient-start` and `icon-gradient-end` belong to the app icon only. Do not use a gradient in the interface.
- Dark appearance: `canvas` is black. Fills with alpha (`fill-track`, `separator`, `accent-tint`) adapt by appearance.

### High contrast

The High contrast theme is an added theme for people who need more contrast. It does not replace Light or Dark, and it keeps their roles and token names.

- Every text color is at least 7:1 on `canvas`, `window`, and `material`: `label` is black, `label-secondary` is #4a4a4a, and `link` and `accent` are #0040a8. Text on `accent` is white, 9.1:1.
- Controls and floating surfaces have a visible outline: `control-border` (#595959) on the FolderControl track, the inactive selected segment, banners, and the status overlay. Banner borders use the full severity color. `separator` is #767676, 4.0:1 or more.
- All `system-*` colors are at least 3.8:1 as marks. `system-red` (#5c000b) and `system-green` (#3a8c16) differ by 3.4:1 in lightness, so a person who cannot tell red from green can still tell error from success. The banner symbols still carry the meaning.
- The app icon gradient and custom editor theme colors do not change.

### Flags

A draft has one flag or none. The flag menu lists: No Flag, Red (1, `system-red`), Orange (2, `system-orange`), Yellow (3, `system-yellow`), Green (4, `system-green`), Blue (5, `system-blue`), Purple (6, `system-purple`), Gray (7, `system-gray`). Show a flag as a filled flag symbol in its color. In a selected row, the flag is `on-accent`.

### Editor syntax colors

- Markdown headings: the theme `heading` color, else `system-blue`. Inline code: `system-orange`. Task boxes: `system-teal`. Links: `system-blue`; in Link Mode, `link`.
- TaskPaper: projects `system-blue`, @tags `system-orange`, @done lines `label-secondary`.
- The built-in editor themes "Default", "Dark", and "Light" have no colors of their own. "Dark" and "Light" only force the appearance; the editor then uses the system colors, which are this system's Dark and Light themes. "Default" follows the system appearance.
- A custom editor theme has three colors: `theme-foreground` (#202020), `theme-background` (#FFFFFF), and `theme-heading` (#007AFF) by default, each six hex digits, plus `isDark`. The name "System" is reserved.

### Type

- Use the system font (`sans`, SF Pro). Do not ship or name another typeface. Use `mono` (SF Mono) only for code and the capture search editor.
- The editor uses `editor-body`, System 17pt. The person can change the font and size in Settings.
- The draft list uses `list-heading` (22pt regular), `row-title` (15pt semibold), `row-preview` (13pt), and `row-meta` (11pt).
- Other UI uses the macOS text styles: `title2`, `title3`, `headline`, `control`, `footer`, `caption`. Use tabular digits for counts.
- The Markdown HTML preview uses `preview-body`: 17px, line height 1.65, max width 760px, 48px top margin, 28px side padding.

### Spacing and layout

- The library window has four panels: sidebar (`sidebar-width` 240px), draft list (`list-width` 280px), editor (flexible), and actions (`actions-width` 260px).
- Fixed bar heights: `utility-height` 48, `list-title-height` 39, `folder-control-height` 28, `tag-strip-height` 45, `editing-bar-height` 31, `footer-height` 29.
- Use the spacing tokens as written. The app uses exact optical values (5, 9, 13, 18px), not a strict grid. Do not round them.
- Default editor margins: `space-5` horizontal, 19px vertical.

### Surfaces, borders, and shadows

- Separate regions with hairlines (`separator`, 0.5 to 1px), not shadows. Draft rows use a 0.5px dashed separator at 45%.
- Floating messages use `material` with a border in their severity color. The only shadow is `shadow-overlay`, on the status overlay.
- Corners: `radius-chip` (6px) for chips and row highlights, `radius-code` (5px) for code, `radius-overlay` (8px), `radius-banner` (10px), and `radius-capsule` for segmented controls.

### States and motion

- Selection: `accent` fill in an active window; `fill-selected-inactive` when the window is inactive.
- Disabled: `label-tertiary`. Actions are disabled while an action runs.
- Focus: use the system focus ring. Custom fields that hide the ring (search, tags) show focus by the insertion point.
- Motion is system default only. The status overlay hides after 4 seconds with no custom animation.

## Iconography

- Draftly uses SF Symbols only: outline symbols at regular or light weight, filled variants for an on state (`flag` → `flag.fill`, `pin` → `pin.fill`, `eye` → `eye.fill`).
- Sizes: 15pt in FolderControl, 17pt in the action bar, 13pt in the footer (12pt for Pin and Link), 20pt light in panel icons inside a 28px hit area.
- Folders: `tray.and.arrow.down` Inbox, `flag` Flagged, `archivebox` Archive, `asterisk` All, `trash` Trash.
- Every symbol-only button has a tooltip and an accessibility label.
- SF Symbols are licensed for Apple platforms and are not in this system. The component previews use simple hand-drawn SVG stand-ins. In the app, always use the named SF Symbol.

## Logos

- The app icon (Logos group) shows two stacked white pages on a blue-to-purple squircle. The menu bar mark is the same two pages as a single-ink template. Use the files as they are.
