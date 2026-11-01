# Default action parity

## Visual review — 1 November 2026

Catalog revision 4 replaces the Stats character-count message with the four
observed steps: reject empty text, calculate nine statistics, set theme colors,
and show an HTML table. Notifications and logs use errors only. An unchanged
legacy Stats action receives the correction on local library open.

The reference action applies English syllable rules and repeated text
normalization. These rules can produce counts that differ from the editor.
The implementation preserves these results instead of substituting another
readability algorithm. With `The cat sat on the mat. This is a simple test.`,
Drafts and the QA app both displayed these values, in table order:
12, 3, 3, 119.8, -2.9, 1, 1.8, -6.6, and 0.8.
Eighteen catalog tests passed, including the observed values, empty text,
unchanged content and modification date, and migration of intact defaults.
The Debug build and strict QA signature check passed.

Stats presentation is not fully accepted. Drafts opens a separate Preview
window with controls above the table. Draftly uses its existing inline preview
with controls below it. The reference loads Vollkorn from Google Fonts; the
local preview uses the available font fallback. Those visual differences remain.

Read-only inspection of Drafts Save Version confirmed `draft.saveVersion();`
and the bar label Version. Catalog revision 3 uses that script and label.
The local migration also replaces an exact unchanged legacy Save Version.
Edited and deleted actions remain unchanged.

Validation passed: 25 core catalog and version contract tests, local Debug
build, and strict QA signature verification. In the isolated QA app, two runs
added two distinct revisions of the same neutral draft. History grew from
three entries to five. Both new entries retained the same 20-character text.
The test also checks that content, modification date, tags, and archive state
remain unchanged. Normal action execution stores the editor selection metadata.

The bar now supports an icon and a nonempty label together. Default dictation
and paste actions use Insert, New, and Paste. An explicit empty label remains
empty. The full action name remains the accessibility label. Thirteen focused
presentation tests passed. QA displayed Insert and New beside native symbols.

Read-only inspection of Drafts Inbox confirmed one script step:
`draft.isArchived = false; draft.update();`. Catalog revision 2 uses this script.
On local library open, an exact revision 1 Inbox separator becomes this action.
The comparison includes all stored fields. Changed or deleted entries remain
unchanged. Cloud libraries and restored copies with new IDs are not migrated.

Revision 2 validation passed: 15 catalog tests and 13 presentation tests, local
Debug build, and strict QA signature verification. On restart, the isolated
QA library changed the original separator to an Inbox button. A neutral draft
was archived, then returned through that button. Archive became empty and
Inbox showed the same draft and text. No personal draft was used.

The action list and editor bar now share default appearance rules. Rules match
the catalog ID, name, and group. They replace an unchanged default symbol and
an unset tint. Custom symbols, explicit tints, and unrelated action IDs remain
unchanged. The rules do not write to the library or change action steps.
Restored copies with new IDs do not receive these display rules.

The editor bar no longer prepends a second set of fixed editing commands.
Editing has 25 catalog actions. Default section dividers appear only in the
list. Imported dividers retain their visibility rules. The list uses rounded
section backgrounds. The five default groups have distinct native symbols or
native symbol-and-text compositions. Group colors no longer depend on selection.

Computer Use compared Basic, Editing, Markdown, Tools, and Processing with
Drafts. The QA app showed the corrected Basic colors, distinct group icons,
and one copy of each Editing action. Some custom Drafts symbols and service
logos remain native approximations. This is not pixel-exact or functional
parity acceptance. The catalog still has functional differences that require
action-by-action review.

The local Debug build and strict QA signature check passed. The focused catalog,
presentation, and editing tests passed: 35 tests in three suites. In isolated QA,
Undo from the editor bar removed neutral test text. Redo from the action list
restored it. The neutral draft remains in the separate QA library.

## Reference

This review used Drafts 54.1.2 (947) on 1 November 2026. Computer Use read the
action list and Settings. It did not run an action, save an action, reinstall a
group, or open a personal draft.

Drafts 54.1.1 (943) remains the archived reference. This review found the same
five default group names. The observed group order is Basic, Editing, Markdown,
Tools, and Processing.

Drafts Settings > Maintenance states that **Reinstall Default Actions** installs
new copies of the five groups. It does not replace existing groups. Draftly uses
the same rule.

## Classification

`supported` means that the shipped Draftly catalog can run the action with its
current engine. `blocked` means that safe parity needs a new service, account
flow, paid service, or non-public contract. This revision has no remaining
`implementable` entries.

The catalog revision is 4. It contains 110 entries, including separators. All
installed steps use supported Draftly step types. Separators keep their observed
names and positions relative to installed actions.

## Basic

| Observed entry | Status | Draftly behavior or reason |
| --- | --- | --- |
| Copy, Share, Mail, Message | supported | Uses the native clipboard, sharing, Mail, and Messages routes. |
| Post to Mastodon | blocked | Needs an account and OAuth contract. Draftly has no Mastodon account service. |
| Google Search | supported | Opens an encoded Google search for the selection or draft. |
| Event | supported | Uses EventKit and asks for access when it runs. |
| Send to Reminders, List in Reminders | supported | Uses EventKit and asks for access when it runs. |
| Print - Plain Text | supported | Uses the native print panel. |
| Services | supported | Separator. |
| Save to Files, Save to Files as... | supported | Uses the existing safe file and export routes. |
| Save to iCloud Drive, Append to iCloud Journal | supported | Uses an explicit `iCloud Drive` folder bookmark. |
| Dropbox actions | blocked | Need OAuth and a Dropbox API client. |
| Save to Google Drive, Append to Google Drive Journal | supported | Uses an explicit `Google Drive` folder bookmark. Google Drive for desktop performs synchronization. |
| Save as Google Doc | blocked | Creating a native Google document needs OAuth and the Google Docs API. |
| Save to OneDrive, Append to OneDrive Journal | supported | Uses an explicit `OneDrive` folder bookmark. OneDrive performs synchronization. |
| OneNote actions | blocked | Need Microsoft authentication and the OneNote API. |
| WordPress and Ghost actions | blocked | Need per-site authentication and publishing contracts. |
| Box actions | blocked | Need OAuth and a Box API client. |
| AI, Using ChatGPT & AI, Apps | blocked | These are separators or guidance tied to Drafts services. Draftly does not copy service marketing entries. |

## Editing

| Observed entry | Status | Draftly behavior or reason |
| --- | --- | --- |
| Undo/Redo, Cursor Movement, Commands, Text Manipulation, Utility | supported | Separators. |
| Undo, Redo | supported | Uses the editor undo manager. |
| Move Left, Move Right, Move Back by Word, Move Forward by Word | supported | Moves the UTF-16 editor selection. |
| Find, Advanced Find | supported | Opens the matching Draftly find interface. |
| Make Tasks, Toggle Tasks | supported | Uses the tested task scripts. |
| Insert Date | supported | Uses the Draftly template date. |
| Insert Dictation, Dictate New Draft | supported | Opens native Draftly dictation only when run. |
| Copy Selection, Paste as Plain Text | supported | Uses the native clipboard. |
| Mail, Message | supported | Uses the selection or the complete draft. |
| Indent, Outdent | supported | Uses the editor indentation preference. |
| Move Line Up, Move Line Down, Duplicate Line | supported | Applies one editor mutation and keeps a selection. |
| Previous Marker, Next Marker | supported | Uses syntax navigation markers. |
| Toggle Theme | supported | Switches between the light and dark modes. |

## Markdown

| Observed entry | Status | Draftly behavior or reason |
| --- | --- | --- |
| Header, Bold, Emphasis, Link, Inline Code, Footnote | supported | Wraps or prefixes the current selection. |
| Block Elements | supported | Separator. |
| List, Quote Increase, Quote Decrease, Code Block | supported | Edits the selected lines. |
| Markdown Table | supported | Inserts a neutral two-column table. |
| Edit Markdown Table | supported | Opens the selected table in a review field, then replaces it atomically. |
| Preview | supported | Uses the current Draftly Markdown renderer. |
| Preview - RTL | supported | Uses the renderer in a right-to-left container. |
| Swiss Preview, Foghorn Preview | blocked | The named Drafts presentation styles are not public Draftly resources. |
| Utility | supported | Separator. |
| Markdown Mail | supported | Renders Markdown and opens Mail with an HTML body. |
| Copy as HTML, Copy as Rich Text | supported | Writes HTML, RTF, and plain-text pasteboard representations. |
| Copy as Rich Text w/o Styles | supported | Writes HTML, RTF, and plain text without Markdown formatting. |
| Paste as Markdown | supported | Inserts plain clipboard text without executing content. |
| Print - Markdown | supported | Renders Markdown and uses the native print panel. |

## Tools

| Observed entry | Status | Draftly behavior or reason |
| --- | --- | --- |
| Change Selection | supported | Separator. |
| UPPER, lower, Title, Sort | supported | Transforms the selection or complete draft. |
| Straighten Quotes, Strip Diacritics, Strip Line Feed | supported | Uses local deterministic text transforms. |
| Hard Wrap, Strip Extra Blank Lines, Trim Whitespace, Remove Blank Lines | supported | Uses local deterministic line transforms. |
| Format Number | supported | Formats a number or percentage with the current locale and a selected decimal count. |
| Smart Parentheses, Smart Brackets, Smart Braces | supported | Wraps the selection. |
| With Options | supported | Separator. |
| Change Case..., Sort Lines... | supported | Shows a review prompt before applying the selected local transform. |
| Encode..., Decode... | supported | Offers URL component and HTML transformations in a review prompt. |

## Processing

| Observed entry | Status | Draftly behavior or reason |
| --- | --- | --- |
| Inbox | supported | Sets `draft.isArchived` to false and saves the draft. |
| Tags & Flags, Templates | supported | Separators. |
| Archive, Trash | supported | Uses the current draft update contract. |
| Save Version | supported | Calls `draft.saveVersion()` to create an explicit snapshot, even when text is unchanged. |
| Stats | supported | Shows nine reference readability statistics in an HTML table. Rejects an empty draft. Preview window and font parity remain pending. |
| Update Tags..., Rename Tag... | supported | Shows a review prompt, then updates the draft or renames the tag across the library. |
| Flag, Unflag | supported | Updates the current draft flag. |
| Workspaces | supported | Separator. |
| Select Workspace, Filter by Tag, New Draft in Workspace | supported | Uses local selection dialogs and the existing workspace routing API. |
| New Draft with Template, Apply Template | supported | Uses create-draft and insert-text steps. |
| Previous Placeholder, Next Placeholder | supported | Selects the previous or next `<|>` marker. |

## Persistence and restoration

A new persistent store receives the current catalog once. Draftly does not use an empty
action list as a signal to seed data. If a person deletes every default action,
the next launch keeps the library empty.

Existing stores do not receive defaults during an update. Automatic seeding runs
only for a new local library without a CloudKit configuration. A new local cache
does not prove that its iCloud library is empty. Cloud-backed libraries wait for
imported actions or an explicit installation. Automatic initialization after a
confirmed empty CloudKit import remains pending; no synchronization acceptance is
claimed by the in-memory configuration test.

Settings > Maintenance
can install explicit copies. Restored groups use names such as `Basic (Default)`
and `Basic (Default 2)`. Each restored group, action, and step gets a new ID. The
write is atomic. A failed write keeps the prior catalog unchanged.

iCloud Drive, Google Drive, and OneDrive actions require folder bookmarks with
those exact names. The user selects each synchronized folder once in Bookmark
Settings. Draftly does not discover a provider folder or request provider
credentials.

### Initial group selection

New windows select the first list-visible group when General is absent. The
panel also checks its selection when it first appears and when catalog data
changes. Existing visible selections and All Actions remain selected. This
prevents the Basic catalog from opening as an empty General list.
