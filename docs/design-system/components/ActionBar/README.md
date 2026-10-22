# ActionBar

A horizontal, scrollable row of colored symbol buttons under the editor that runs editing commands and actions from the selected group.

Source: `Sources/Draftly/EditorActionBar.swift`. This card is an HTML rendition.

## Use

- The first control is a menu that selects the action group. "Editing" is always first.
- Each button has a tooltip and an accessibility label with the action name.
- An action shows its symbol unless its bar label is set to text. Then it shows the label in 13pt.
- A separator action shows a 1 x 18px divider.

## Consumer provides

- The window model, the editor session, and the library with ordered actions and group names.

## Tokens

- Height `editing-bar-height` (31px); `space-12` horizontal padding; `space-20` between buttons.
- Symbols: 17pt regular in a 22px frame; group menu symbol 21pt light in `label-secondary`.
- Default colors by command: Move Left/Right `system-yellow`; word, Indent, Outdent `system-orange`; Toggle Tasks `system-purple`; Find and Dictation `system-green`; others `system-blue`.
- An action's tint overrides the default: none (`label`), gray, red, orange, yellow, green, blue, purple, pink, each mapped to its `system-*` token.
