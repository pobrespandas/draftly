# Theme installation and replacement review

`themes.install` and `themes.replace` still lack direct handlers. Do not advertise
them as connected operations.

## Input decoding

`ThemeInstallation.decodeDefinition` provides one bounded decoder for native and
Drafts JSON. The file-theme reader now uses it. The caller supplies a byte limit
before decoding. The decoder requires UTF-8, validates the definition, preserves
native unknown fields, and retains the Drafts source for export. File access still
sets the installed file identity and type after decoding. The parser does not
open files, fetch URLs, create bookmarks, save definitions or change selection.

## Host integration still required

- Resolve inline text, connection-owned transfers, authorized bookmark paths and
  HTTPS inputs. Do not accept arbitrary local paths. Network reads need the
  native effect authorization route.
- Validate installation URLs with `ThemeInstallation` and handle built-in names.
- Keep custom and file modes distinct. File mode requires a saved bookmark.
- Bind replacement to the existing target version and resource scope. Reject
  conflicting identities or names before saving.
- Validate optional selection against its separate appearance token. Do not
  broaden resource grants to a new definition or editor.
- Commit durable request identity with the library mutation. Recover the original
  result before reading an input again. Do not repeat uncertain network effects.
- Preserve native cross-store ordering and report uncertain partial outcomes.
  Library records, bookmarks and selection do not share one transaction.
- Test interruption, concurrency, revocation, transfer ownership and installed
  native behavior before release acceptance.

## Decoder validation

The 23 focused format and file-access tests passed. Regression passed all 826
Core tests and 10 app tests for selection, reload and reviewed deletion. The
native Debug build passed. Logs: `/tmp/draftly-theme-input.log`,
`/tmp/draftly-theme-input-regression.log` and `/tmp/draftly-theme-input-build.log`.
These checks validate the shared decoder. They do not validate installation or
replacement handlers, which remain absent. Coverage remains 112/137.
