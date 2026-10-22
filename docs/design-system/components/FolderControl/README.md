# FolderControl

A capsule segmented control that selects the draft folder: Inbox, Flagged, Archive, All, or Trash.

Source: `Sources/Draftly/VisualControls.swift` (`FolderControl`). This card is an HTML rendition of the SwiftUI view.

## Use

- Put it under the folder heading in the draft list, 10px from each side, `folder-control-height` (28px) tall.
- Use it for the five fixed folders only. Do not add segments.

## Consumer provides

- `folder`: a binding to the selected `NoteFolder`.

## Anatomy and tokens

- Track: `fill-track` in a `radius-capsule` shape.
- Selected segment: `accent` fill with `on-accent` symbol. When the window is inactive, the fill changes to `fill-selected-inactive` and the symbol to `label`.
- Unselected symbol: `label` at 85%, 15pt regular SF Symbol.
- Divider: 1 x 16px `divider-segment`, only between two unselected segments.
- Each segment has a tooltip and an accessibility label with the folder name. The selected segment has the selected trait.
