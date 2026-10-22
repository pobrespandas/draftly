# EditorFooter

The bottom strip of the editor with draft utilities, the syntax menu, and live text statistics.

Source: `Sources/Draftly/EditorFooter.swift`. This card is an HTML rendition.

## Use

- Order: Pin, Draft Info, Version History, Action Log, Arrange menu, Link Mode, then a spacer, Preview, Syntax menu, statistics.
- A toggle that is on (Link Mode, Preview) shows its symbol in `accent`. Off toggles stay `label-secondary`.
- Every control has a tooltip. Preview names its shortcut: "Preview Markdown (⌥⌘P)".

## Consumer provides

- The window model, the editor session, and the library (for syntax names).

## Tokens

- Height `footer-height` (29px); `space-12` horizontal padding (6px under 360px wide, 4px under 280px).
- Gap `space-13`; `space-6` when the footer is narrower than 360px.
- Symbols 13pt in a 14px frame; Pin and Link 12pt. Syntax menu 12pt (11pt compact). Statistics `footer` 11pt with tabular digits.
