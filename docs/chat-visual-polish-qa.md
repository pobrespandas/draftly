# Chat visual polish

## Changes

- Let the chat composer use a transparent native editor background.
- Keep the main draft editor background unchanged.
- Add a rounded composer surface, border, and empty-state hint.
- Use compact response actions with symbols and accessible names.
- Disable Insert when no draft is available.

## Checks — 2026-11-11

- `swift build --product Draftly` passed.
- `git diff --check` passed.
- An isolated app used a separate bundle ID and temporary library.
- A fixed conversation showed Markdown headings, lists, quotes, and code.
- Light and dark modes showed no black rectangle in the composer.
- Six input lines enabled internal scrolling. The panel footer separators
  stayed aligned as the composer grew and returned to its empty height.
- No prompt was sent. No model connection was created. The normal library
  was not opened by this QA app.

## Limits

The isolated build exposed Copy but did not expose the production draft action
callbacks. Create draft and Insert were compiled, but were not invoked in this
visual check. Keyboard input automation dropped accented characters. This check
does not establish Unicode input acceptance. The fixed Markdown fixture did
show accented text and an emoji. This change is not published.
