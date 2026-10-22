# TagChip

A small rounded label that shows one draft tag in the editor tag strip or in a draft row.

Source: `Sources/Draftly/VisualControls.swift` (`TagCapsuleField`) and `Sources/Draftly/DraftListPanel.swift` (`DraftTableRow`). This card is an HTML rendition.

## Use

- Show tags in the order the draft stores them. Tags are normalized by `TagRules` before display.
- In the editor, a click on the chip row switches to the native token field to edit tags.
- Do not use chips for status or counts.

## Consumer provides

- `tags`: an array of tag strings.

## Variants and tokens

- Editor: 12pt `tag-strip`, 16px tall, `accent-tint` fill, 0.5px `accent-tint-border`, `radius-chip` continuous corners, `space-4` between chips.
- List: 11pt `row-meta`, 14px tall, accent at 10% fill and 25% border.
- In a selected row, the fill is clear, the text is `on-accent`, and the border is white at 65%.
