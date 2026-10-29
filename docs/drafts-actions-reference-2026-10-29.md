# Drafts action references — 29 October 2026

The original action and group payloads were downloaded for local research. They
are not included in the website. The Draftly actions use independent scripts.
They provide a subset of the reference behavior, not full parity.

| Reference | Source | SHA-256 of downloaded JSON | Draftly action |
| --- | --- | --- | --- |
| Sort Lines | https://directory.getdrafts.com/a/12I | `add4baa155b6db0b3ed8a4706e90c6d325cc87bbb6f54abdff5531cef76014d0` | Sort Selected Lines |
| Append Text to Lines | https://directory.getdrafts.com/a/163 | `ef65f610468494a692957fdba17d6ab39432af87ed8c89480b6f2fe4cead40e2` | Append Text to Selected Lines |
| Markdown group | https://directory.getdrafts.com/g/1Ce | `f528464bea7d78a0b037d056f9bf2c8b2faf1f6c47fe3ea6ca98553b5af979f0` | Make Selection Bold, Emphasize Selection, Copy Markdown as HTML |
| Editing group | https://directory.getdrafts.com/g/1Ba | `6f77ef850c73ac6753de770abbc68a42ee6e06ce89bc84011b291908a10bbdb7` | Research reference; no new action from this group in this batch |

The downloaded payloads are in the ignored local research evidence directory.
The Sort Lines reference offers case sensitivity and other destinations; the
Draftly action offers ascending and descending replacement. Append Text to
Lines targets selected lines in Draftly. Markdown wrappers require a selection.
The HTML action copies rendered HTML as text.

`swift test --filter OwnWritingActionsTests` passed eleven methods, including
imports, selected lines, Unicode, sort cancellation, and Markdown output. Native
dialogs, Undo, and clipboard acceptance for this batch remain pending.

## Selected integration references

| Reference | Source | SHA-256 of downloaded JSON | Draftly prototype |
| --- | --- | --- | --- |
| PDF Export | https://directory.getdrafts.com/a/1FV | `6b6814868d2c42fdf36e263cd9624d9faf6a56d8092936fded4175ee7dc88b10` | Print Markdown to PDF |
| Send to Things | https://directory.getdrafts.com/a/1Cc | `5f9c30ee5e33167f1b5e8e798986dd1ffbaf5c83e9f6d28010f0a6559fb4de97` | Send Draft to Things |
| Things Parser | https://directory.getdrafts.com/a/1DV | `2b7032e1750da86260c6fe5c6935a75269506878291cd7b5bc2ebdcb53f48b87` | Send Simple TaskPaper List to Things |

These prototypes implement only a small subset. PDF uses the Mac print dialog
and requires the user to select Save as PDF. The Things draft action opens Quick
Entry with the first line and body. The simple TaskPaper action accepts only
unindented task lines without tags. It rejects unsupported input before opening
Things. Neither action supports the original project parsing or all metadata.
The original PDF action also depends on an external Workflow.

The Things URL format follows https://culturedcode.com/things/support/articles/2803573/.
The `OwnWritingActionsTests` suite passed fourteen methods after these additions.
It uses simulated print and URL hosts. Native PDF output, Things installation,
permission prompts, delivery, and Things results remain unverified.

## Markdown outlines for Things

`things-markdown.json` adds an independent prototype for the Send to Things
outline format. It maps project headings, task headings, task lines, checklist
items, notes, destination names, tags, start dates, and deadlines to Things
JSON. A test exercises one project with a heading, task, notes, checklist, tag,
start date, and deadline on both runners. Invalid orphaned items fail before
opening a URL. This is not complete compatibility: more source variants,
callback success and error behavior, limits, and real Things delivery remain
unverified. The prototype was not added to the published catalog.

`swift test --filter OwnWritingActionsTests` passed fifteen methods after this
change. Both Things and printing use simulated hosts in these tests.

## TaskPaper and PDF follow-up

The TaskPaper prototype now maps supported project and heading nesting, tasks,
notes, checklist items, completion states, dates, tags, and destination fields.
Unknown tags and Mustache prompts fail before the Things URL opens. The source
contains other syntax and Mustache behavior; full parity and live Things delivery
remain open. The markdown outline and TaskPaper tests use both action runners
and a simulated URL host.

The `writingActionGeneratesRealMarkdownPDF` app test ran the actual action and
native print layout to generate a local one-page PDF without panels. PDFKit
extracted the heading, accented text, and emoji. This does not verify the print
dialog, Save as PDF interaction, all formatting, or multiple pages for this
action. `swift test --filter OwnWritingActionsTests` passed sixteen methods after
the TaskPaper changes. A first run exposed an unsafe Mustache handling path; the
prototype now rejects it and the confirmation run passed.

## Mustache, callbacks, and PDF dialog follow-up

The TaskPaper prototype now prompts for basic text, boolean, and date Mustache
variables and renders simple sections. It rejects unsupported expressions, such
as date offsets, before opening Things. A cancelled prompt keeps the draft and
opens no URL. These cases passed with simulated prompts on both runners. This
is not full Mustache Prompt parity; escaped values, date offsets, and additional
section and input variants need reference comparison.

The Markdown outline prototype now waits for a Things callback. Simulated
success, cancellation, and error cases passed on both runners. Things was not
installed for this check. The TaskPaper prototype retains the original action's
non-callback URL opening behavior. No real Things delivery is accepted.

In isolated QA, File > Import loaded `print-pdf.json`. The action opened the
native print panel. PDF > Save as PDF saved a one-page file in a new temporary
folder. `pdftotext` found the neutral title, `café`, and emoji. The app reported
completion and retained the draft text. No printer or personal library was used.
The resulting file remains at `/tmp/draftly-pdf-export-qa-H0CuWr/Draftly PDF
QA.pdf`. QA quit normally. The exact app registration was removed after ZIP
verification. Recovery: `DraftlyRecovery/pdf-action-20261029-033448`; the
neutral QA library remains under UUID `97A27A01-0C61-4083-B227-EC21806552C3`.

`swift test --filter OwnWritingActionsTests` passed nineteen methods after these
changes. One earlier run failed because two test assertions selected the wrong
host operation; the corrected tests passed. This is focused evidence, not full
compatibility or a complete regression run.

## Add Draft to List

`add-to-list.json` is an independent action inspired by Add to List
(https://directory.getdrafts.com/a/1Ga). It appends nonempty source lines as
unchecked tasks to a selected `list` draft, or creates an archived list with
that tag. It excludes the current draft from destinations. After success it
archives the source draft. Empty input, invalid new names, and cancellation do
not archive the source. The two dialogs differ from the original action.

Focused tests cover existing and new lists, Unicode, source archive, cancellation,
empty input, and invalid names on both action runners. `swift test --filter
OwnWritingActionsTests` passed twenty-two methods. Native dialogs and Undo for
this action remain unverified.

## Obsidian export actions

Two independent actions use the `Obsidian Vault` folder bookmark. Save Draft
in Obsidian Vault creates a Markdown file in the selected folder. It uses the
safe draft title and fails if that name already exists. Append Draft to
Obsidian Daily Note appends to `YYYY-MM-DD.md` in the selected folder, using
the current date. It creates the file if it is absent. It does not locate a
custom daily-note folder or change the draft after success.

References downloaded for local research:

- Save in Obsidian Vault: https://directory.getdrafts.com/a/1qn, SHA-256
  `1d80acc814b0fd8d1d1063baca4bcc3feaa2569e9b18bf816bbb63f96b0247f8`.
- Add to Obsidian Daily Note: https://directory.getdrafts.com/a/2EO, SHA-256
  `4d6d4af4ca25feee44da71936534889c1fa569aa9c0ded0bcfded9f34a37c394`.

The `OwnWritingActionsTests` suite passed twenty-four methods. It checks action
import, both runners, file names, contents, write modes, and failure with a
simulated host. The separate native adapter test
`bookmarkedExportPreservesAllWriteModesAndCreateProtection` passed with a
temporary folder. It checks create, append, prepend, replace, and existing-file
protection. These tests do not verify a real Obsidian vault, folder selection,
or Obsidian's daily-note configuration.

## Notion and Day One actions

Copy Draft and Open Notion copies the complete draft as plain text and opens
`notion://`. It does not archive the source, unlike the reference action. If
opening fails after copying, the copied text remains on the clipboard. The
Notion destination and receipt were not checked with the app.

Send Draft to Day One opens `dayone://post?entry=` with the encoded draft. It
keeps the source draft. A successful URL opening does not confirm an entry was
saved. The Day One URL format is documented at
https://dayoneapp.com/guides/tips-and-tutorials/day-one-url-scheme/.

References downloaded for local research:

- Copy to Notion: https://directory.getdrafts.com/a/1JO, SHA-256
  `aa52b1a8ec3be93d29ac8368e43e3dfe02ff7435cae5ffedcf803a5e9b80fde9`.
- Send to Day One: https://directory.getdrafts.com/a/1CR, SHA-256
  `262f3cc79df844a92bf1fd1f0f57a267d00b0e2e56400a318154b4dc46c21747`.

`swift test --filter OwnWritingActionsTests` passed twenty-seven methods. New
cases check both runners, Unicode and URL encoding, empty drafts, clipboard and
URL failures, and source retention with simulated hosts. No external app was
opened, and no native clipboard or external delivery is accepted by this test.

## Bear and daily journal actions

Send Draft to Bear uses a callback URL to create a note from the first line and
body. Send Daily Notes to Day One sends a dated heading and the draft body with
Daily and Notes tags. Both keep the source draft. Unlike the Drafts Daily Notes
reference, the Day One action uses the default journal and does not archive.

References downloaded for local research:

- Send to Bear: https://directory.getdrafts.com/a/1CZ, SHA-256
  `13cfd8fc9757846e4dd0e79332c62c54b5c8e213d3de57289ec7a25a97459ad0`.
- Daily Notes: https://directory.getdrafts.com/a/1Ij, SHA-256
  `c07747b845fc9fa875518659cc007b426b6ee88f420f8753ba4697be4b7766fb`.

URL references: https://bear.app/faq/x-callback-url-scheme-documentation/ and
https://dayoneapp.com/guides/tips-and-tutorials/day-one-url-scheme/.
`swift test --filter OwnWritingActionsTests` passed twenty-nine methods. New
cases cover both runners, URL encoding, callback success, cancellation and
error, dates, tags, empty drafts, and source retention with simulated hosts.
Bear and Day One delivery, permissions, and saved entries remain unverified.
