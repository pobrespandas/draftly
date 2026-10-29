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
