# Draftly writing actions QA — 29 October 2026

The three action files in `website/public/actions` imported together through
File > Import in an isolated local QA app. The QA library used a new UUID and
neutral text. The usual app and library were not used.

- New Draft from Template showed the template selector. Select created a new
  draft with the template text. Cancel kept the draft count and current text.
- Transform Selected Text showed uppercase and lowercase choices. Uppercase
  changed `café` to `CAFÉ` beside an emoji. Command-Z restored the original text
  and selection. Cancel kept the text unchanged.
- Copy Markdown as Rich Text first produced incorrect UTF-8 text in TextEdit.
  The action now declares UTF-8 in its HTML. After reimport, TextEdit received
  `Hello café` and showed Bold for the selected text. A separate paste confirmed
  an accented character and emoji. Other formatting remains unverified.

`swift test --filter OwnWritingActionsTests` passed seven methods. The tests
cover import, both runners, Unicode selection, missing template, cancellation,
and simulated clipboard success and failure. Native QA does not establish all
input, clipboard destination, or Undo variants.

QA quit normally. The exact QA bundle was unregistered after ZIP verification.
The recovery archive is `DraftlyRecovery/own-actions-20261029-025254` in the
user's Application Support. The neutral QA library remains in the temporary
`Draftly-UITesting` directory under UUID
`24CED650-7FE8-443F-BCF6-B04A3870226F`.
