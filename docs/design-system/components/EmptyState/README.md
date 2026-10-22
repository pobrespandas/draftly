# EmptyState

A light symbol and one short line that fill an empty panel.

Source: `Sources/Draftly/PanelEmptyState.swift`. This card is an HTML rendition.

## Use

- Write the message as a fact about the panel, without a period: "No action selected".
- Do not add buttons. Put commands in the panel toolbar.

## Consumer provides

- `message`: a string.

## Tokens

- Symbol: `curlybraces`, 32pt light. Text: `control` (13pt). Both in `label-secondary`.
- `space-10` between symbol and text; `space-64` from the panel top; centered horizontally.
