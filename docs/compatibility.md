# Action compatibility

## Reference snapshots

The fixture manifest records the source URL and SHA-256 hash of each downloaded
action. Tests import the original JSON and run the original scripts.

| Action | Directory ID | Verified behavior |
| --- | --- | --- |
| New Draft with Template | 1VL | Query templates, show a selection prompt, create a draft, copy tags, render date tags, and select a placeholder |
| Add to List | 1Ga | Share variables across steps, select a list, append items, and archive the source |
| Text Modifier… | 1Bg | Read a text selection, show options, replace text, and move the cursor |
| Copy as Rich Text | 1DM | Render Markdown and pass HTML to the rich text clipboard operation |
| Save in Obsidian Vault | 1qn | Render the file name and body, use a named folder bookmark, and keep create mode |

The automated tests replace native side effects with a test host. A passing test
does not prove that an external app, account, or permission is available.

## Supported bridge

- `Draft`: create, find, query, content, tags, archive, trash, flag, syntax, update,
  dates, location metadata, versions, action logs, tasks, and template tags.
- `editor`: text, UTF-16 ranges, selection, replacement, load, and activation.
- `Workspace`: create, find, save, tag filters, date filters, query, draft views,
  and sort orders.
- `Prompt` and `SelectPrompt`: buttons, text fields, dates, numbers, switches,
  pickers, and multiple selection.
- `context`: configured values, cancellation, and failure.
- `app`: messages, clipboard, HTML clipboard, URLs, action queue, and workspace.
- `Action.find`, `Base64`, `Share`, `FileManager`, `Credential`, Markdown rendering,
  `HTMLPreview`, `Shortcut`, and `AppleScript`.
- HTTP requests, callback URLs, shell scripts, and script imports with `require`.
- Calendar, reminders, speech, location, and native model sessions.

HTML previews run inside Draftly. They can return form values and continue or
cancel an action. Included actions share the parent JavaScript context. The
runner checks included steps before it starts. Cancellation stops queued actions.

Action scripts use MultiMarkdown 6.8.0, cmark-gfm 0.29.0.gfm.13, and Mustache
4.2.0. The vendor manifest records their sources and hashes. MultiMarkdown uses
separate token allocations, as its library header recommends for host apps.
Markdown Settings select the default processor for editor previews and Action
templates. Explicit script engine objects keep their own options.

This list describes a subset of each object. Other Drafts properties and methods
are not guaranteed. Missing methods fail in JavaScript. A failed or cancelled
action does not apply its after-success behavior. Changes made by earlier steps
remain saved. There is no rollback of external side effects.

Credential values use this Mac's Keychain. They are not part of backups or
CloudKit records. Password fields hide their text.

FileManager paths refer to the Draftly Library folder. Named export bookmarks
refer to folders chosen on this Mac. Credentials and folder permissions are not
imported from Drafts.

Workspace installation links with an existing identity require confirmation
before they replace different local settings. Identical links do not replace
the record. Cancellation and a concurrent change retain the installed record.
Native QA has verified cancellation; native replacement remains to be checked.

The JavaScript runtime applies a ten-second CPU execution limit when macOS exports
the JavaScriptCore limit function. Synchronous native dialogs wait for user input.
This limit uses a runtime symbol and is intended for personal distribution.
The bridge is not a security sandbox for untrusted actions.
Asynchronous script completion has a separate 120-second timeout. Native services
require their macOS permissions. Automated tests do not grant those permissions
or prove that each service works on this Mac.

Compatibility work remains. Some URL mutations, mail recipient options, and
the chat console need further work. XML-RPC and directory-based Mustache
templates now have implementations and targeted tests. They do not prove full
compatibility with all servers or template libraries.
HTML-to-Markdown conversion supports a subset of HTML. Third-party service
connectors and iOS-only APIs are outside this scope.

## Import and export

The importer accepts Draftly action JSON, Drafts action JSON, groups with an
`actions` array, directory URLs, and Drafts installation links. It preserves the
raw payload, disabled steps, and unknown step values. Disabled steps do not run.
Native action, step, and presentation records also retain unknown JSON fields
at their original level. Known typed fields take priority over collisions.
It does not claim
compatibility with every Drafts export version or extension type.

Templates support draft content, title, body, safe title, selection, tags,
hashtags, UUID, permalink, dates, and custom tags. Unknown tags stay in the text.
File templates can load local template files. Service wrappers, custom syntaxes,
and themes require further compatibility work.

## Roadmap implementation pass — 2026-10-19

The reference inventory is `docs/research/action-api-matrix.json`. It records
529 members from 44 official API pages. The installed UI reference is Drafts
54.1.1. Each page has a URL and source hash. Most members remain marked
`not-audited`; that status does not mean missing or supported. Explicit test
and live-check fields hold separate evidence. Do not count the inventory as
complete API coverage.

XML-RPC supports raw XML requests, nested values, faults, and explicit transport
errors. Tests cover encoding and response parsing, plus an invalid transport
through JavaScript. No live XML-RPC server was used. Date and binary interop
with real servers still needs acceptance checks.

Mustache directory templates load named `.mustache` files and sibling partials.
Tests use a host that supplies template files. Live iCloud Drive access remains
unverified. The template path cannot leave the Templates folder through `..`.

Action options now include descriptions, visibility, confirmation, notifications,
sections, order, and after-success tags and flags. New optional fields preserve
old action and backup decoding. Imports map known description, confirmation, and
assigned-tag fields. Unknown visibility bit masks and notification enums remain
in the raw payload; they are not claimed as mapped options.

Action groups have records for names, symbols, and order. Backups include them
through an optional field. Renames keep the saved group identity and update its
actions. Local changes do not change the Core Data entity schema. Sync behavior
for the new records still needs the two-Mac checks.

The global Capture shortcut and standard macOS shortcuts remain fixed. The main
app commands have local configurable shortcuts. Both the action inspector and
the command editor use the same conflict validator.

## Core audit — 2026-10-19

See `docs/research/core-actions-audit.md` for corrections and remaining limits.
The normalized matrix now includes exact signatures and member kinds. It keeps
manual evidence during refresh. The 149 core and helper entries have review
records and targeted test associations. They are not a claim of full parity.

`Draft.query` now uses the documented omitted-tag array and ascending default.
The previous boolean fourth argument remains accepted. Scripting color labels
now match the existing Draftly UI indices. Existing stored values do not change.
Workspace filters use the same rules in script queries and the visible list.
Script text edits register native undo immediately. `ActionExecutionResult`
provides one final result for existing entry points; `run` remains a boolean
adapter. Access-date operations fail explicitly. Full syntax grammar and native
entry-point acceptance remain open.
