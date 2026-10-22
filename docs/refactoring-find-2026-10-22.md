# Advanced Find refactoring — 22 October 2026

## Reference and base

The clean reference is 11e8955. Main matched origin/main. The annotated tag is
pre-refactor-find-2026-10-22. No earlier work was discarded. No build, test or
QA process was active at the start. The installed app remains unchanged.

Before editing, complete serial runs passed 650 app and 650 Core methods.
Separate fresh reports match all 1,300 discovered identities. All 68 Python
tests and the local Xcode build passed. Logs and reports stay in /tmp under
draftly-find-refactor-*. Earlier concurrent worker and window-opening timing
risks remain recorded. No retries or production timeout changes belong here.

## Accepted boundary

AdvancedFindView currently renders fields and results and also performs editor
selection, navigation, replacement, synchronization and saving. Extract only
those commands into AdvancedFindCommands. Keep query options, bindings, errors,
result previews, focus and dismissal in the view. EditorFindQuery remains the
existing matching and replacement engine. No public API or new search engine
is needed.

Preserve current behavior:

- Navigation uses UTF-16 ranges and the safe editor selection. Previous uses
  a strict comparison with the selection start. Next starts at the selection
  end and excludes an identical match. Both directions wrap.
- A zero-length match advances without adding a character offset. A single
  zero-length match can select itself again. No results cause no effects.
- Selecting a result synchronizes the editor without saving or changing focus.
- Replace All updates content, clamps selection, synchronizes, reports the
  change and flushes, in that order. Invalid queries do nothing. A valid query
  with no matches still follows the existing command sequence if called; the
  view separately disables its button.
- A failed save retains changed editor text, the error and unsaved state.
  It does not add rollback. Undo and Redo keep their current native bridge.

The domain model is unchanged. Search acts on the current draft, not on the
draft-list selection. Native find and preferAdvancedFind routes stay unchanged.
No stored schema, backup format, identity, syntax rule or script changes.

## Stages

1. Extract the commands and characterize navigation, zero-width results,
   Unicode selection, empty results and isolation between editors. Run affected
   tests and local compilation before the scoped implementation commit.
2. Characterize replacement order, literal and regex results, persistence,
   failures and native Undo/Redo. Reuse only the existing offscreen Undo fixture
   and disconnect it explicitly. Keep existing contract test names.
3. Verify complete Swift reports against inventory, Python tests and matrix
   structure. Run local compilation without overlapping Swift tests. Perform a
   separate isolated manual QA check. Update architecture, status and handoff.

## Results

1. Commands extracted. Four characterization methods cover forward/backward
   boundaries, wrapping, zero-width matches, missing/invalid results and current
   editor isolation. All 34 affected app methods and five Core query methods
   passed. Local Xcode compilation passed. Independent review found the command
   comparisons and effect order unchanged. Query state, previews and focus stay
   in the view.
2. Replacement integration: six methods cover exact publication/callback/save
   order, literal and regex composition, durable reopening, selection after
   shortening/deletion, invalid queries, valid no-match commands, save failure,
   explicit retry and real native Undo/Redo. All 49 affected app methods and
   five Core query methods passed. Local compilation passed. Independent review
   found no weakened assertions or unnecessary duplicate cases. Native editor
   fixtures have no window and are disconnected in defer.

Complete integration and the separate manual check are next.

The accepted functional and compatibility backlog remains separate.


## Integrated automatic results

All 660 app methods in 119 suites and 650 Core methods in 124 suites passed
serially. Fresh per-target Swift Testing reports match discovery. All 1,300
baseline method identities remain. Ten new methods cover the extracted command
boundary. No test was deleted or renamed. All 68 Python tests passed. The normal
matrix structure check has zero errors. The final local Xcode build passed.
No Swift test run overlapped compilation. No retries or changed deadlines were
used. The earlier concurrency risks remain separate; this is serial acceptance.

Core source, public APIs, syntax, persisted definitions, backup and library
formats, signing configuration and original action fixtures have no diff from
the reference. The generated Xcode project only adds the internal app source.
API compatibility classifications stay unchanged. Passing tests do not establish
new Drafts parity, native integration or iCloud acceptance.

## Manual results

Computer Use used a fresh QA app with an isolated preferences domain and local
library. It published no Services, URL scheme or document types. CloudKit and
global capture shortcuts were disabled. The habitual app was not opened by this
check or replaced. No permissions, messages or sounds were involved.

Verified in use:

- Paste the neutral source `🐼 café CAFÉ\ncafé Tail`. Advanced Find starts with
  empty fields and unchecked options. Literal café finds three results.
- Select the third result. Next wraps to the first. Previous wraps back to the
  last. Temporary screenshots showed the corresponding result highlights.
- Match Case reduces the count to two. Replace All with té produces exactly
  `🐼 té CAFÉ\nté Tail`; the uppercase occurrence stays unchanged. Done closes
  the sheet and the editor shows the result.
- Undo restores the original Unicode source and its selection. Redo restores
  the replacement. The draft row updates after the existing save delay.
- Native Find opens after Advanced Find closes. Searching té selects it.
  Native Done closes its bar without changing draft content or list filters.
- Advanced Find can open again. A regex query `[` shows the existing error,
  disables commands, and leaves text unchanged after Escape.

The first Quit shortcut was rejected after a Computer Use context change.
A fresh state contained additional QA text and no selected draft. Those later
states are not credited as expected command output or as a reproduced product
defect. Quit from the application's menu succeeded. Process absence was checked
before retiring the exact Launch Services record. The bundle, exported
preferences and closed library were moved together to recoverable Trash.

Manual scope does not include an induced storage failure, all regex variants,
Pro-only comparisons or full Drafts parity. Save failure, retry and zero-width
boundaries have separate automatic evidence above. Captures and raw logs were
not added to Git.

QA identity: `com.pobrespandas.draftly.find-refactor-qa-b92ac458`.
Debug implementation SHA-256:
`fb48b7789e283d07fadd9ede25daef4726ee00468513d97280bef9b60744e973`.
Session metadata: /tmp/draftly-find-refactor-qa.json. Temporary paths can disappear
after restart; this document preserves the conclusions and limitations.

## Closure and resume point

The extraction, replacement tests and documentation have scoped atomic commits.
The reference tag and validated commits are published. All accepted refactoring
changes are complete. No new product regression was demonstrated in these
checks. Earlier work and branches remain intact. The installed app is unchanged.

Cloning remains paused. When feature work is requested, resume the existing
Editor and scripting backlog: syntax-defined tasks, markers, links, custom
grammars and advanced-find compatibility acceptance. Keep inspector options,
native integrations and Pro-only comparisons separate. This stage does not
complete those contracts or Draftly as a whole.
