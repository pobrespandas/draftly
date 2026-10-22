# DraftRow

One draft in the draft list: a semibold title, preview lines, optional tags, flag, and modified date.

Source: `Sources/Draftly/DraftListPanel.swift` (`DraftTableRow`) and `Sources/Draftly/DraftRowPresentation.swift`. This card is an HTML rendition.

## Use

- The first line of the draft is the title. The other nonempty lines are joined with " • " as the preview.
- When a search query is active and preview of matches is on, the preview shows matching lines as `N: text` in semibold.
- Swipe shows Trash and Archive. Archived rows show Inbox, and trashed rows show Restore.

## Consumer provides

- `note` (content, tags, flag, dates), `title`, and the list options: `showPreview`, `previewLines` (1 to 3), `showTags`, `showDate`, `showLastAction`, `highlightFlagged`.
- `emphasized`: true when the row is selected in a focused list.

## Measurements and tokens

- Insets: 7px top, 6px bottom, 6px leading, 10px trailing; `space-2` between lines. Two preview lines give the `row-pitch` of 81px.
- Type: `row-title` 15/17 semibold, `row-preview` 13/16, `row-meta` 11 for tags and date, `row-last-action` 10.
- Colors: title `label`, preview `label-secondary`, date `label-secondary` at 65%. Selected: `accent` fill, `on-accent`, `on-accent-secondary`, `on-accent-tertiary`.
- Flag: 13pt filled flag in the flag color (see Flags in the brand book). With `highlightFlagged`, a 1px border in the flag color at 60%, `radius-chip`.
- Separator: 0.5px dashed (1, 1) `separator` at 45%, hidden on the selected row.
