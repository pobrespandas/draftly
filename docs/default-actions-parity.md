# Default action parity

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
current engine. `implementable` means that the behavior is reasonable but is
not in this catalog revision. `blocked` means that safe parity needs a new
service, account flow, paid service, or non-public contract.

The catalog revision is 1. It contains 94 entries, including separators. All
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
| Save to iCloud Drive, Append to iCloud Journal | implementable | Needs an explicit user-selected destination. Do not assume an iCloud folder. |
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
| Edit Markdown Table | implementable | Needs an interactive table editor. |
| Preview | supported | Uses the current Draftly Markdown renderer. |
| Preview - RTL | supported | Uses the renderer in a right-to-left container. |
| Swiss Preview, Foghorn Preview | blocked | The named Drafts presentation styles are not public Draftly resources. |
| Utility | supported | Separator. |
| Markdown Mail | supported | Renders Markdown and opens Mail with an HTML body. |
| Copy as HTML, Copy as Rich Text | supported | Writes HTML, RTF, and plain-text pasteboard representations. |
| Copy as Rich Text w/o Styles | implementable | Needs a separate style-removal contract. |
| Paste as Markdown | supported | Inserts plain clipboard text without executing content. |
| Print - Markdown | supported | Renders Markdown and uses the native print panel. |

## Tools

| Observed entry | Status | Draftly behavior or reason |
| --- | --- | --- |
| Change Selection | supported | Separator. |
| UPPER, lower, Title, Sort | supported | Transforms the selection or complete draft. |
| Straighten Quotes, Strip Diacritics, Strip Line Feed | supported | Uses local deterministic text transforms. |
| Hard Wrap, Strip Extra Blank Lines, Trim Whitespace, Remove Blank Lines | supported | Uses local deterministic line transforms. |
| Format Number | implementable | Needs locale and formatting choices. |
| Smart Parentheses, Smart Brackets, Smart Braces | supported | Wraps the selection. |
| With Options, Change Case..., Sort Lines..., Encode..., Decode... | implementable | Need review dialogs and explicit option contracts. |

## Processing

| Observed entry | Status | Draftly behavior or reason |
| --- | --- | --- |
| Inbox, Tags & Flags, Templates | supported | Separators. |
| Archive, Save Version, Trash | supported | Uses the current draft update contract. |
| Stats | supported | Displays a local character count. |
| Update Tags..., Rename Tag... | implementable | Need review prompts and library-wide rename confirmation. |
| Flag, Unflag | supported | Updates the current draft flag. |
| Workspaces | implementable | Separator will ship when its related actions ship. |
| Select Workspace, Filter by Tag, New Draft in Workspace | implementable | Need selection dialogs and workspace routing. |
| New Draft with Template, Apply Template | supported | Uses create-draft and insert-text steps. |
| Previous Placeholder, Next Placeholder | supported | Selects the previous or next `<|>` marker. |

## Persistence and restoration

A new persistent store receives revision 1 once. Draftly does not use an empty
action list as a signal to seed data. If a person deletes every default action,
the next launch keeps the library empty.

Existing stores do not receive defaults during an update. Settings > Maintenance
can install explicit copies. Restored groups use names such as `Basic (Default)`
and `Basic (Default 2)`. Each restored group, action, and step gets a new ID. The
write is atomic. A failed write keeps the prior catalog unchanged.

Google Drive and OneDrive actions require folder bookmarks with those exact
names. The user selects each synchronized folder once in Bookmark Settings.
Draftly does not discover a provider folder or request provider credentials.
