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
- `Workspace`: create, find, save, tag filters, date filters, query, and folder sorts.
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
The editor preview uses a separate renderer.

This list describes a subset of each object. Other Drafts properties and methods
are not guaranteed. Missing methods fail in JavaScript. A failed or cancelled
action does not apply its success disposition. Changes made by earlier steps
remain saved. There is no rollback of external side effects.

Credential values use this Mac's Keychain. They are not part of backups or
CloudKit records. Password fields hide their text.

FileManager paths refer to the Draftly Library folder. Named export bookmarks
refer to folders chosen on this Mac. Credentials and folder permissions are not
imported from Drafts.

The JavaScript runtime applies a ten-second CPU execution limit when macOS exports
the JavaScriptCore limit function. Synchronous native dialogs wait for user input.
This limit uses a runtime symbol and is intended for personal distribution.
The bridge is not a security sandbox for untrusted actions.
Asynchronous script completion has a separate 120-second timeout. Native services
require their macOS permissions. Automated tests do not grant those permissions
or prove that each service works on this Mac.

Compatibility work remains. XML-RPC, directory-based Mustache templates, some
URL mutations, mail recipient options, and the chat console need further work.
HTML-to-Markdown conversion supports a subset of HTML. Third-party service
connectors and iOS-only APIs are outside this scope.

## Import and export

The importer accepts Draftly action JSON, Drafts action JSON, groups with an
`actions` array, directory URLs, and Drafts installation links. It preserves the
raw payload, disabled steps, and unknown step values. Disabled steps do not run.
It does not claim
compatibility with every Drafts export version or extension type.

Templates support draft content, title, body, safe title, selection, tags,
hashtags, UUID, permalink, dates, and custom tags. Unknown tags stay in the text.
File templates can load local template files. Service wrappers, custom syntaxes,
and themes require further compatibility work.
