# StatusOverlay

A transient caption over the editor that confirms a command, then hides after 4 seconds.

Source: `Sources/Draftly/VisualControls.swift` (`EditorStatusOverlay`). This card is an HTML rendition.

## Use

- Use it for confirmations that need no action. Use MessageBanner when the person may need to read or dismiss the text.
- It does not take clicks. A new message restarts the 4-second timer.

## Consumer provides

- `message`: a string. An empty string hides the overlay.

## Tokens

- `caption` text, up to 3 lines; `space-12` horizontal and `space-8` vertical padding; `material` fill; `radius-overlay` (8px); `shadow-overlay`; 12px margin from the editor edge.
