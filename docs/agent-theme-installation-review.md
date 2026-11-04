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

## Prepared installation and replacement

`AgentThemeImportPlanning` accepts a trusted resolved input. It checks the request
schema, library binding, capabilities, resource scope, identity and name conflicts.
It carries a validated definition, optional file permission and optional selection
intent. It does not resolve a source, save a definition or select an appearance.
The input owner must prove that the resolved input belongs to the requested source.

New installation cannot silently overwrite an installed identity or same-type
name. The caller must use explicit replacement with the current target token.
Replacement keeps the target ID and theme type. It cannot consume another
installed identity or name. File replacement uses the effective `themes.get`
token; the existing authorized file is read to validate that token. Built-in input
must match its installation link and cannot replace an installed record.

Optional selection requires its own appearance token. This token does not replace
the target definition token. The effect owner must revalidate the same prepared
input and current target/selection at the final commit boundary. It must recover
the durable result before resolving the original source again.

Three new tests cover eight conflict/authority scenarios, both file plan forms,
and built-in link binding. Together with selection and reload regression, all
11 tests in two suites passed. Native Debug passed. Logs:
`/tmp/draftly-theme-import-plan.log` and
`/tmp/draftly-theme-import-plan-native.log`. The handlers remain unavailable.
Source resolution, durable effects, multi-store recovery and installed acceptance
are still required. Coverage remains 112/137.
