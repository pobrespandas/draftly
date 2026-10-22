# Draftly implementation and remaining work

Updated: 22 October 2026.

## Cloud QA preparation refactoring

R5 is implemented in the [Cloud QA preparation record](refactoring-cloud-qa-preparation-2026-10-22.md).
Metadata rules, file operations and CLI entry now have explicit boundaries.
The CLI keeps its identities, UUID reuse and backup/write behavior. Eight
characterizations passed before and after extraction; the specific suite has
12 tests. Final verification passed Core674/app777, Python80, local Debug build
and structural matrix. The initial Core baseline had a pre-host-start failure;
its focused check and the final full run passed. This risk remains separate.
No native cloud run or app update occurred. Strict engine diagnostics remain 18.
Editor styling is the next proposed refactoring.

## Workspace preparation refactoring

R4 is implemented in the [Workspace preparation record](refactoring-workspace-preparation-2026-10-22.md).
The common private preparation operation leaves saving, cancellation and
application in their callers. Four characterization methods passed before
extraction. Final checks passed Core674/app777, Python68, 51 focused methods,
local Debug compilation and the structural matrix. No native session or app
update was needed. Strict engine diagnostics remain 18. The later R5 stage
records Cloud QA preparation.

## Editor completion refactoring

R1 is implemented in the [completion-context record](refactoring-completion-context-2026-10-22.md).
Completion data now has an explicit lazy provider, independent of Touch Bar.
Characterization passed before extraction. Final checks passed Core674/app773,
Python68, 56 focused methods, local Debug build and the structural matrix.
There was no new native manual session or installed-app update. The prior
XML-RPC timing risk and the 18 strict engine diagnostics remain separate.

## Modularity audit

The [repository audit](modularity-audit-2026-10-22.md) is complete at the
architectural level. It proposed five bounded refactorings. R1 completion
context, R4 Workspace preparation and R5 Cloud QA preparation are implemented
separately. Styling and text synchronization remain. The audit itself changed no
production or test code and removed no tests. The documentation now distinguishes current orientation from
historical records. Complete verification on 1e399dd passed Core674/app767,
Python68, local Debug compilation and the structural matrix check. Native
acceptance and the prior XML-RPC timing risk remain separate.

## Latest refactoring

The [native sharing lifetime refactoring](refactoring-native-lifecycle-2026-10-22.md)
separates the action wait from service-resource retention. Final verification
passed Core674/app767, Python68 and the local Debug build. The initial concurrent
Core baseline had a pre-transport XML-RPC timeout; its focused serial check and
the final complete run passed. This prior risk remains recorded. No new native
acceptance or installed-app update occurred. Strict engine diagnostics remain 18.

## Current Actions engine acceptance

Sharing discovery now checks cancellation and one absolute deadline before it
can show a picker. Controlled red/green cases cover available and unavailable
services, expiry and temporary-file cleanup. Core674/app762 and local Debug
compilation passed for that boundary check. A later owner-binding correction
passed Core674/app765 and local Debug compilation. Native URL picker Cancel,
missing-owner rejection with another window open, file cleanup and following
shell recovery passed. QA was retired recoverably; the usual app stayed intact.

Async printing now uses its action window after external confirmation. The
previous missing-key-window failure is fixed; missing owners cannot borrow
another window. Core674/app759, Python68 and local Debug build passed. The real
118-page PDF completed, followed by shell recovery. QA was retired recoverably.
Native print owner-close and other route obligations remain separate.

Reminders default-list access returned an explicit denied outcome through a
system-delivered App Intent, then succeeded through URL with a Boolean availability
parameter only. Following Intent recoveries passed. The user later confirmed
the prompt and pressing Allow. Pending-authorization cancellation and late-grant
isolation stay open.
QA was retired and Shortcut parameters restored. No reminder or list was created.

System-delivered App Intent shell checks now passed Stop cancellation, the
production120s timeout and direct owner-window close. Each removed the confirmed
parent/child and private files, stopped later steps and allowed a new Intent
recovery. Closed history matched all six runs. QA was retired; the existing
Shortcut parameters were restored. Other native capabilities remain separate.

Native URL Shortcuts cancellation and the production 60-second timeout passed
with the actual CLI process and private-file cleanup. Each returned one matching
callback, stopped later steps and allowed shell recovery. The neutral Shortcut
was restored to five seconds. Internal service-job stop remains unobserved;
system-delivered Intent variants stay separate. QA was retired recoverably.

Native URL transcription now passed after a user-granted speech permission.
Synthetic neutral audio returned one success, with matching callback and editor
text. Following real shell recovery passed. QA was retired recoverably.
Model readiness still returned unavailable. Recognition denial, timeout and
late-result acceptance remain separate. Six engine contracts remain partial.

Apple model requests now check absolute deadlines before generation, tool access
and response delivery. Synchronous cancellation state closes the queued-cleanup
gap. Red/green injected cases, Core674/app754, Python68 and local Debug build
passed. Native model generation remains pending; six engine contracts remain
partial. No usual-app deployment or native model acceptance is claimed.

A clean native print check confirmed the source-close restriction: Close was
disabled and Close All left the sheet and source window open. Panel Cancel and
following shell recovery returned one matching callback each. This is not
owner-close acceptance. Repeating that same Close All path cannot close the
remaining native case without a change in application or system behavior.

Print callback delivery now checks synchronous task-cancellation state. Both
normal callback answers are rejected after cancellation, with owned-presentation
cleanup once. Red/green headless cases and the complete Core674/app750 run passed,
with local Debug compilation. Native print owner-close acceptance remains open.

Native speech source-window close now passed during the completion notice and
while the helper was confirmed live. Both cancelled without success effects
and allowed recovery. A later short-phrase run held its callback until OK, then
returned one success. Direct audible-output confirmation and system-delivered
Intent variants remain separate. QA apps were retired after the complete repeat.

Actual Intent.perform now has speech-process cancel and timeout coverage with
real silent helper processes. It verifies cleanup before return, typed errors,
retained writes, no later steps or Archive and a successful following Intent.
The new full run passed Core674/app749 and local Debug compilation. System
delivery of the Intent remains separate. The prepared manual speech owner-close
check was completed after unlock, as recorded above.

Waited process cancellation now has synchronous state at exit delivery and a
second check before spawn. Red/green process tests cover cancelled launch,
normal-status rejection and remaining-child cleanup. The prior full checks passed
Core674/app748 and local Debug compilation. Native entry acceptance remains
separate. Python was unchanged; the earlier68-test result was not rerun.

Async speech synthesis now runs in an owned helper process. Native URL task
cancellation and the production timeout return their final callback without
blocking MainActor. Both remove the helper and private files and allow a
following successful action. A later native synthesis result completed successfully. Independent audible
output confirmation remains separate. The usual app is unchanged.
The prior integrated checks passed Core674/app745, Python68 and local Debug build.
This does not complete the six partial engine contracts.

A prior integrated check also covers transcription and EventKit callback
deadlines and EventKit cancellation cleanup: 674 Core and 733 app methods
passed with complete report inventories and local Debug compilation. Native
permission and capability checks remain separate.

The earlier integrated check includes dictation permission and speech completion
cancellation races, plus actual Intent shell cleanup: 674 Core methods, 720 app
methods, 68 Python tests and local Debug compilation passed. Native permission
checks remain separate. Cancellation now blocks late dictation grants before
they can request the next permission or start recording.

Actions work resumed after the refactoring stages below. At 709821e, integrated
checks passed 674 Core methods, 716 app methods, 68 Python tests and local Debug
compilation. Swift reports matched discovery. These totals do not establish
contract parity. The strict engine gate retains six partial contracts and 18
diagnostics. Native acceptance is tracked in
[the remaining route checklist](research/engine-native-checklist.md).

Notes sharing timeout, file retention and a late provider cancellation passed
with a following action isolated from that old provider. Task cancellation and
owner closure after handoff remain pending. Mail now fails explicitly instead
of reporting composition as a confirmed send. Confirmed delivery remains partial.
Messages also reported false sent before actual sending. Its adapter now rejects
unconfirmed delivery before composition. Message.send remains partial; a native
URL error and following recovery passed. The latest complete check passed
674 Core, 724 app and 68 Python tests plus local Debug compilation.
The habitual app has not received these QA changes. Historical pause statements
below describe their own refactoring stages.

## Current Advanced Find refactoring stage

Cloning remains paused. The
[Advanced Find refactoring record](refactoring-find-2026-10-22.md) records the
completed extraction from clean 11e8955. AdvancedFindCommands owns selection,
navigation and replacement effects. The view keeps state, errors and focus;
EditorFindQuery, native find and preference routes stay unchanged.

Complete checks passed 660 app methods, 650 Core methods and 68 Python tests,
local Xcode compilation and matrix structure validation. Every baseline method
identity remains. Manual navigation, Match Case, replacement, Undo/Redo, invalid
regex and native-find coexistence passed in isolated QA. The shutdown context
change is recorded separately. QA was closed and retired without replacing the
habitual app. Failed saves and retry have headless tests, not induced native
acceptance. No Drafts compatibility status is promoted by this stage.

## Previous option refactoring stage

Functional cloning is paused at the user's request. The
[option refactoring record](refactoring-options-2026-10-22.md) owns the current
diagnosis, reference tag and acceptance results. Step creation defaults now have
an app owner. Core supplies shared value rules through the ActionEditing SPI.
Prompt and Create Draft tests share only their identical headless setup.
Existing public signatures, imported data and storage formats stay unchanged.

The integrated Core check exposed an unchanged XML-RPC test fixture waiting
after its server exited. A separate test correction now retains that exit event
and fails explicitly if it is absent. The incomplete run remains recorded.
Final checks passed 650 Core methods, 650 app methods and 68 Python tests, plus
local compilation and the matrix structure check. All baseline test identities
remain. Manual copy/save/cancel, Prompt output, background creation, Undo/Redo
and the final type picker passed in isolated QA. QA was closed and retired;
the habitual app was not replaced.
No feature or compatibility status is promoted by this refactoring.

## Functional checkpoint before this refactoring

Draftly works as a local Mac app. Mac parity is not complete. Cloning resumed
from 026cfbb after the completed inspector/personalization refactoring stage.
The user now prioritizes functional completion: Actions end to end, editor and
scripting, the action inspector, integrations, then Settings and personalization.
The visual/daily-flow delivery remains open. Inspector-created configurationKey
steps now work through save, first-use cancel/accept and restart reuse. Typed
runner checks passed. See the latest section in actions-engine.md. Full serial
verification passed 646 Core / 637 app methods; the initial concurrent Core run
had five worker-test timeouts and remains recorded separately. The includeAction
UUID is now editable without changing the step identity. Cancel, Save and actual
retargeted execution passed in QA. The include-target complete app run passed 639 methods. Create Draft now has an
Open in Editor switch. Background creation preserved native source text and
Unicode selection. Its complete app run passed 641 methods. Ordinary SelectPrompt now supports
Up/Down from Search. Native direction changes, Return-to-script and Escape
passed. Its complete app run passed 642 methods. No new Drafts comparison was
made for that keyboard improvement.
Native action-host bookmark read/write and reuse after process restart now passed
in fresh Functional QA. Picker Cancel retained the draft, and History showed
Cancelled / Success / Success. Permission loss and iCloud Drive remain open.
Configure Window now exposes its seven controls and three references in the
inspector. Both runner flows and reference-error preflight passed. Native save,
execution, retained Unicode selection, Undo/Redo and edit Cancel passed for the
recorded subset. Its complete app run passed 645 methods. Full step parity stays
open. See actions-engine.md for the exact scope.
The first-party Prompt step now exposes its documented options and defaults.
Native inspector-to-dialog Cancel and second-button/text tag output passed.
Both runner flows and error cases passed. The latest complete app run passed
650 methods; local and signed builds passed. Full Prompt-step acceptance remains
open for the listed variants. The habitual app is unchanged.
The earlier delivery covers the main window, daily flows and personalization.
Read [the delivery record](ui-flows-2026-10-21.md) for separate implementation,
automatic, native and pending results. Capture receipt/append, File commands,
Workspace sort, list preference ownership and shortcut/font fixes are committed.
The measured pass aligns five list titles, row pitch and editor text at
1200 by 800 points against Drafts. New reference captures at 1033 by 734 and
850 by 600 points are valid at 2x. The action-inspector separator now tracks the third real split boundary.
Measured central toolbar offsets improved to 10–12 points, but still exceed the
current three-point target. Right toolbar alignment is still being refined.
The latest checked complete run passed 646 Core and 633 app methods. Python: 68.
Local Debug and signed Release passed. An initial new Spotlight test found unstable payload order;
its identity-order correction passed focused and complete checks. Prior engine
timing fragility remains documented, without retries or deadline changes.

Implemented and tested: Workspace management routing, opt-in Spotlight indexing,
editor line-height/paragraph spacing and custom Touch Bar support. Specific
Markdown, HTML and bookmark contracts now have separate tests. Native Workspace
lifecycle checks passed for the two named QA definitions. Spotlight result
opening, native Settings persistence and the remaining visual matrix stay open.
Workspace application now rejects malformed presentation references before any
change. Built-in theme picker identity matches the resolver. Normal theme scope
backgrounds are applied. Invalid paragraph preferences render safely. Typewriter
centers short and empty documents without clearing selection or Undo. Specific
regressions and previous-implementation failures are in the delivery record.
Native Workspace group/theme application, stale-name UUID resolution, explicit
reference rejection and backup restoration passed in isolated QA. The focused
results are in the delivery record. Other native boundary and Settings checks
remain pending.
The host has no Touch Bar. Do not treat headless construction as hardware
acceptance. Native daily-flow checks passed for Quit without explicit Save, Capture Append
with two windows, selection and Undo/Redo, Quick Search cancellation and Capture
without a main window. The original 50 note IDs and texts were checked against
the final exported backup. Native storage-failure and empty-clipboard checks
remain pending. The user selected a three-point visual tolerance and prioritized
data retention and daily flows. The habitual app is unchanged by this delivery. Do not install yet.
Settings font-size and margin labels now reject unsafe integer conversions.
Specific numeric-limit tests passed. This does not validate nonfinite font or
layout rendering.
User window closure now vetoes failed saves before the scene delegate runs.
Specific failure/retry and delegate tests passed. Normal native close/reopen
passed with two neutral QA notes. Quit with stale duplicate editors still needs
a separate check. See the latest delivery section.
The earlier [refactoring record](refactoring-editing-2026-10-21.md) retains the
four completed extractions and their evidence.
Historical sections below retain their original scope and dates.
Keep the identity Draftly, `Note`, existing identities and libraries, original
action scripts, Nerd Fonts, and the integrated Markdown preview.

## Main app identity — 21 October 2026

The main app now uses `com.pobrespandas.draftly`, with the same display name,
team and existing CloudKit container. The signed Release is installed at
`~/Applications/Draftly.app`. Local preferences migrate before app initialization.
Read [the migration record](bundle-identity-2026-10-21.md) for separate automated,
native and pending results. The previous UI refactoring stage is complete.
This delivery does not close any remaining cloning contracts.
Read [the QA cleanup record](qa-cleanup-2026-10-21.md) before recreating old
installations. Six QA apps were moved to Trash and 22 obsolete build directories
were removed. Fixtures, data, profiles and verified legacy package archives remain.

## Previous work — UI boundary refactoring

The user requested behavior-preserving refactoring before more feature work.
See [the accepted diagnosis](refactoring-ui-2026-10-21.md) for four bounded stages,
the validated baseline and preserved checkpoint. The shared sort writer, inspector field policy and test-only theme-reader stages
and preference fixture stages are complete. Final checks passed: 630 core methods,
531 app methods, 57 Python methods and unsigned compilation. All baseline test
identities remain. See the record for closure and the exact cloning resume point. Functional Workspace defects
and native acceptance remain separate. This does not close the Mac roadmap.

## Current delivery order — 21 October 2026

The current order is main window and daily flows, then Workspaces, Settings
and personalization, followed by validation and signed installation. Keep outstanding
engine and API checks open; do not substitute these deliveries for them.

The action step inspector now exposes Enabled through the existing isEnabled
field and marks disabled rows. It edits the temporary action copy. Imported
platform values remain preserved but are not evaluated by the engine. Their
semantics and editor are pending. The wider inspector delivery stays open.

## Latest correction — local scene draft reference, 21 October 2026

Implemented: each LibraryView stores its current draft UUID in local SceneStorage.
A restored scene can load that draft before creating an empty draft. An explicit
opening target or existing editor wins. Missing IDs are ignored. This state is
local UI data; library and backup formats do not change. The app does not force
macOS to reopen windows.

Automatically tested: four headless tests cover saved identity, UTF-16 selection,
unchanged content history, invalid/missing IDs, access-write failure/retry and
existing target/pending-edit preservation. Checked runner verified 623 core and
524 app methods. Unsigned Xcode build passed. Matrix structure remains valid.

Verified in use: refreshed QA and repeated sequential tab success. Native full
restoration remains pending. One menu snapshot exposed Quit and Keep Windows,
but Computer Use could not reliably invoke it. Option-Command-Q did not terminate
the verified process. No system preferences changed and no force quit was used.
Closed test tabs; Alpha remains open with five unchanged drafts. Continue other
Window/native contracts while retaining this acceptance gap.

## Latest access audit — Window Workspaces, 21 October 2026

Implemented: no additional production change. The exact Window getter and apply
access now have their own evidence. Three both-runner tests cover typed detached
snapshots, query-based sort independence, default/explicit forwarding, Boolean
results and host failure before later edits. They do not accept every Workspace
rule. The complete run is 623 core and 520 app methods. Matrix structure0;
strict global4107 remains open, not a percentage.

Verified in use: the selection fixture read a typed Inbox snapshot, changed its
query locally and observed an unchanged query on the next read. Success08:03.
No new native apply was performed. Native application from this access, malformed
snapshot errors and wider Workspace parity remain pending.

## Latest correction — real Window list selection, 21 October 2026

Implemented: WindowModel owns selectedDraftIDs. The native table and scripting
read the same selection. selectedDrafts returns visible selected rows in list
order, without replacing the current editor draft. Empty selection stays empty.
Editor identity changes update selection immediately; reloading the same draft
does not collapse a multiple selection.

Automatically tested: three both-runner model contracts failed before connection
and passed after it. A fourth test checks editor identity updates. Full working-
tree run verified 623 core and 520 app methods, including the separate Workspace
access suite. Unsigned Xcode build and matrix structure passed.

Verified in use: Zulu and Excluded selected while Alpha stayed open; scripting
received both in visible order. Empty selection returned no drafts while Alpha
remained open. Success08:03/08:04. No content or flags changed. Restart check
showed Untitled with one tab after quitting with three; it did not exercise
restoration of prior scene IDs and does not accept restoration. Data remained.
Continue native scene restoration and the remaining Window contracts.

## Latest correction — confirmed tab opening, 21 October 2026

Implemented: a typed library scene carries a unique opening request. The worker
awaits the exact scene, draft selection and native tab attachment. Removed the
0.2-second search for an arbitrary new window. A concrete registry handles single
completion, deadline, cancellation and retired requests. Window registration now
follows actual view attachment. The legacy runner keeps its separate synchronous
adapter. Normal worker opening does not poll RunLoop.

Automatically tested: eight registry, four adapter/controller and three worker
methods cover confirmation, rejection, independent requests, cancellation,
timeout and late results. Checked runner verified 620 core and 516 app methods.
Unsigned Xcode build and matrix structure passed. Strict engine/global remain
18/4127 diagnostics. Counts are not compatibility percentages.

Verified in use: native fixture opened Zulu and Excluded sequentially into the
origin tab group, with three correct titles and target content. The source Alpha
stayed unchanged. History Success07:54. Closed test tabs with Command-W; Alpha
remains. Deliberately slow native creation, pending origin close, concurrent native
requests, restoration and URL/Intent variants remain pending. Window parity is
not complete. Continue those paths and the remaining contracts.

## Latest correction — stable action group references, 21 October 2026

Implemented: Window group loaders and Workspace use one concrete resolver. A
UUID selects its current group name. Missing or malformed identities cannot
fall back to another group with the old name. Name-only references still work.
Unknown Workspace reference fields remain intact.

Automatically tested: three parameterized model tests cover both Window loaders,
actual rename and name reuse, Workspace equivalence, missing/malformed IDs and
unchanged presentation on failure. The first two failed before the correction.
Checked runner verified 617 core and 504 app methods. Unsigned Xcode build passed
after regenerating the project to include the new source. Matrix structure0;
strict global4136 remains open, not a percentage.

Verified in use: native prepared-state fixture loaded QA Identity renamed into
the action list and checked bar selection from a reference with its old name.
Success07:43; Alpha unchanged. This native fixture is a final-state snapshot;
the actual rename is tested headlessly. Window group contracts remain partial
for undefined failure behavior and list-visibility comparison with Drafts.
Next: replace unconfirmed tab success with correlated native scene completion.

## Latest native acceptance — file save lifetime, 21 October 2026

Implemented: no production change. Added neutral file lifetime fixtures.
Automatically tested: all 14 NativeFileSelectionTests passed headlessly. The
previous checked 617-core/501-app run and unsigned build remain the source
baseline. Matrix structure passed; strict engine remains open with 18 diagnostics.

Verified in use: Actions task cancel closed the native Save panel. The unchanged
120-second production timeout also closed it and recorded an error. Earlier
writes remained in Inbox; later insertion and Archive did not occur. A following
Save wrote the exact 35-byte Unicode output. Neither interrupted target existed
after recovery. Real stale callback delivery, owner close, bookmark restart and
permission paths remain pending.

Read-only review found separate Window defects: tab opening reports success
before native completion, and group loading resolves only names. Correct stable
group references first with a regression. Tab opening needs correlated scene
completion; a source-window Boolean alone cannot prove success.

## Latest correction — initial search queries, 21 October 2026

Implemented: scripted Quick Search and Command Palette now use initialQuery.
The search dependency carries the exact string to a new view state. The palette
uses window-local query state. Normal entry points and omitted arguments clear
previous queries. Library filters remain separate.

Automatically tested: two new model regressions failed before the adapter fix
and passed afterward. They cover Unicode, omitted arguments, independent list
and action filters, source text and selection. The checked runner verified
617 core and 501 app methods. Unsigned Xcode build and matrix structure passed.

Verified in use: refreshed and signed isolated Engine QA. Four fixture actions
showed the exact initial queries, the matching results and empty fields on the
next no-argument call. Cancel kept Alpha open. History recorded four Success
results at 07:31–07:32. No QA Services registered. Window members remain partial
for host errors and other native cases. Continue remaining Window contracts and
file-panel lifetime acceptance. The complete Mac roadmap remains open.

## Latest correction — Window bridge, 21 October 2026

Implemented: Window void commands no longer expose the host Boolean return.
Visibility and tab-availability properties have getters only. floatOnTop keeps
its setter. Boolean group and tab methods keep their existing return path.

Automatically tested: four new member tests run through both runners. Three
failed before the correction and all four now pass. The checked full runner
verified 617 core methods and 499 app methods. Unsigned Xcode build passed.
Fifteen Window members have specific bridge evidence but remain partial.

Verified in use: no new native check or QA refresh. Native member acceptance and
host-error cases remain pending. The query commands forward initialQuery in the
bridge, but WindowActionAdapter ignores it. Fix this defect independently, with
its own regression test. Strict engine/global gates remain 18/4154 diagnostics.
These counts do not measure compatibility. Continue native file-panel lifetime
checks and remaining Window contracts.

## Latest contract review — HTMLPreview, 21 October 2026

Implemented: no production change. The four archived HTMLPreview members now
have individual contract records. Constructor and create are complete for their
argument-free construction contract. hideInterface and show remain partial.

Automatically tested: four new member tests run through the legacy runner and
serial worker. They check independent instances, default and changed visibility,
exact HTML, Continue/Cancel Boolean results, returned context values, and
presentation failure before subsequent editor changes. The checked runner
verified 613 core methods and 499 app methods. Matrix structure passed.

Verified in use: retain the earlier native preview lifetime checks. This review
does not add a native run. Hidden-toolbar comparison, actual stale WebKit message
delivery and entry-specific URL/Intent checks remain pending. Strict engine and
global gates still fail with 18 and 4274 diagnostics. These are not percentages.
Continue with Window member contracts and native file-panel lifetime checks.

## How to read this status

- **Implemented** means the code exists. It does not imply complete parity.
- **Automatically tested** means specific assertions passed.
- **Verified in use** means a recorded native check passed for that case.
- **Pending** includes missing code, incomplete contracts, and native checks.

The [API matrix](research/action-api-matrix.json) owns individual member evidence.
The [visual matrix](research/visual-parity-2026-10-19.json) owns visual acceptance.
[Validation](validation.md) and the [core audit](research/core-actions-audit.md)
retain historical results. Later results supersede earlier counts.

## Current verification

URL fragment/hostname writes now update their serialized URL and related host
fields. Both-runner regressions and native QA passed. Constructor is complete;
encoding/normalization and other edge cases keep the remaining members partial.
The checked runner verified499 app/609 core; unsigned Xcode passed.

Native explicit-text Arrange task cancel and production timeout now close the
dialog and preserve completed writes without later edits or Archive. A following
Done result passed. Owner-close and stale-navigation checks remain open.

The checked Swift runner now requires fresh xUnit results for every discovered
method. A real run verified499 app methods and604 core methods by identity.
Nine guard tests and all56 Python methods passed. App tests default to serial;
core and explicit task-concurrency contracts remain concurrent. Concurrent app
reporting is still unresolved. No production or QA bundle changed in this stage.

Native HTML preview task cancel, owner close and production timeout passed on
the current QA image. Completed writes stayed Inbox without tail/Archive; fresh
responses remained isolated. An old scheduled timer did not finish or contaminate
the new preview. Actual stale WebKit delivery was not observed; direct late
request rejection has headless coverage. No production preview code changed.

HTML.unescape now preserves literal CRLF/CR, NUL and surrounding text while
decoding entity tokens. Three red byte cases now pass; native QA passed.
Sequential app499 and concurrent core604 methods plus unsigned Xcode passed.
Concurrent app runs exited0 without a final summary and are not accepted as
complete. HTML constructor is complete; escape/unescape comparison stays partial.

Base64 encode/decode now have specific contract records. Independent UTF-8 and
standard vectors pass both runners; native QA checked values and unchanged text.
Full concurrent498 app/601 core passed. No production implementation changed.
Undocumented malformed-input behavior has no parity claim.

AppleScript production timeout now passed on the signed QA image. The helper
and private directory were removed, completed text stayed in Inbox without
tail/Archive, and a following native action succeeded. Permission variants and
Date argument comparison remain pending; execute stays partial.

Current-image native AppleScript task cancel and owner close now passed. Exact
helpers and temporary directories disappeared. Completed writes stayed in Inbox
without tail/Archive; a following native action succeeded. Native timeout and
Automation permission variants remain pending. Execute stays partial.

Host cleanup test streams now finish when the action returns before the expected
signal. A regression checks early failure and a following run on the same
library. Focused tests and full concurrent498 app/599 core passed. Production
drain behavior did not change. The exact historical stall cause is not proved.

AppleScript results now preserve Date objects, including nested lists/records,
through the helper, both bridges and native steps. Specific headless tests and
two native QA actions passed. Four construction/property members are complete;
execute stays partial for its remaining argument/permission/interruption checks.
Full sequential regression passed498 app/598 core and unsigned Xcode. The
concurrent-suite stall remains open. Strict engine/global remain18/4412.

Removed duplicate Services from the five installed QA copies. Finder now shows
only the two ordinary Draftly capture entries and the two Drafts entries. QA
refresh removes NSServices before signing;47 Python methods passed. The normal
app declarations and all QA libraries remain unchanged.

AppleScript.execute now preserves fatal interruption in the legacy bridge.
Three red cases showed later edits and Archive before correction. Four specific
methods now pass on both runners. Full sequential regression passed496 app and
590 core methods; unsigned Xcode passed. The concurrent full run stalled and
remains a test-runner investigation. Native date conversion and native acceptance
of this correction remain pending. AppleScript.execute stays partial.

ShellScript now returns false for ordinary execution failures while retaining
fatal cancellation/timeout. Six member-specific methods passed in both runners,
and native status/streams/launch-failure checks passed. Four value/stream members
are complete; execute remains partial for its scripts-directory/access contract.
Final regression passed 496 app and 586 core methods and the unsigned build.

Shell arguments now retain their exact Unicode composition in both native
adapters. Byte-level tests exposed and fixed the Foundation argument conversion.
Native nonzero status/streams and process-group cancellation passed after the fix.

Completed PDF printing exposed and fixed an AppKit worker/MainActor crash.
The shared print operation now renders on MainActor. A headless PDF regression
and two real Save as PDF runs passed, with the action continuing after Save.
Native task cancellation and the print panel Cancel button each closed the panel,
recorded Cancelled and preserved completed text without the tail or Archive.
A following action succeeded. The unchanged production120s timeout also closed
the panel and recorded Error without tail or Archive. Owner close and large
rendering stay open.

The six partial engine records point to the finite
[native engine checklist](research/engine-native-checklist.md). It separates
18 route families, permission cases and unresolved inclusion/import comparisons.
Recorded UI/URL/Intent acceptance remains valid for its tested scope.
Native shell UI cancellation, owner close and production timeout now passed,
including parent/child cleanup, retained writes and a successful following action.
Shell-specific URL/Intent variants and other route cases remain pending.

Selected-file themes now support a chosen development folder. Direct supported
files are validated together and saved in one library operation. Source identity
survives reload and name changes. Launch, activation and manual reload refresh
the folder. Local bookmarks stay outside backups. Invalid files preserve the
previous records and rendering. Automatic standard-folder discovery and
continuous watching remain pending.

Signed isolated QA passed custom light/dark rendering, configured slots after
restart, Settings consistency, folder selection, file rendering, changed-source
reload, invalid-file recovery and native Undo/Redo. External theme URLs passed
installation, Cancel, Replace, identity/unknown-field checks and identical
reimport without an alert. Native file-specific reload, moved-source following,
reselection with stable UUID,
cross-window refresh and folder discovery after restart also passed. Forced stale
bookmarks, sandbox permissions and remaining Drafts comparisons stay pending.
The earlier
QA native-pipe and temporary-app URL registration failures are retained in the
validation history. Theme contracts remain partial.

Full regression passed 494 app and 580 core methods, 46 Python tests and the
unsigned Xcode build. These totals do not establish parity. See the latest
validation entry and individual matrix evidence. The six Theme members are a
dated supplement; the archived baseline remains unchanged.

app.selectDraft now applies Workspace filters, sort, initial editable query
and row options. Specific tests and native QA selection/cancellation checks
passed, including a corrected Escape wait. Share has a dated reference
supplement: its filename-first API and Boolean results are corrected. Native
file cancellation passed. Completed-service and legacy sharing remain partial.
See the latest validation records and member evidence in the API matrix.


The four App display-message methods now return void and show severity banners
in the owning window. Both-engine and headless routing tests pass. Native QA
verified all four messages, close, expiry, history and text preservation.
Context.fail native result checks passed, but visible OS notification delivery
remains pending. See the latest records in validation.md.


Nine refactoring stages are validated: pure catalog rules, isolated bookmark
preferences, shared test execution support, Workspace sort mutation,
configuration default selection, auditor source indexing and pure editing-bar
text calculations, native asynchronous routing and window-submission ownership.
See [stage results](refactoring-2026-10-21.md#stage-results) for current checks
and [remaining risks](refactoring-2026-10-21.md#remaining-refactoring-and-risks)
for retained boundaries and separate functional work. Cloning has resumed.

The refactoring base is `a415883`, tagged `pre-refactor-2026-10-21`.
Swift baseline: 455 app methods and 502 core methods passed. Matrix structure
has zero errors. Strict engine acceptance retains 18 existing diagnostics.
See [the refactoring record](refactoring-2026-10-21.md) for tool-environment
results and later stage checks.

The functional `Action.find` duplicate-name correction was selected from local
WIP `35a790c` after refactoring. Its specific automatic and native restart checks
passed on 21 October. Only Action.find is accepted; installation-contract work
from that WIP remains separate. It was not part of the refactoring base. Other Mac
contracts remain pending. The API matrix owns current member classifications;
test totals are not a compatibility percentage.
The new line-up text no-op has a separate local reproducer at `3af40f2` on
`agent/wip-editor-line-up-2026-10-21`. That test is intentionally failing;
there is no correction in it and it is not in main. See the refactoring record
before applying either functional WIP.

## Architecture refactoring completed 19 October 2026

The baseline tag `pre-refactor-2026-10-19` is published on origin. The six code
stages are implemented. See [architecture](architecture.md) for component
responsibilities, dependency direction, and acceptance. Current work preserves
behavior. Native visible acceptance was deferred under the background test policy.

Three tests that displayed and moved windows were removed. Hidden window tests
now reject ordering and activation. Shared fixture synchronization replaces
repeated queue-draining helpers. A new test covers tag changes across injected
peer windows. The final suite passed 170 app and 267 core tests.

API classifications and the original action scripts are unchanged. Mac parity,
async execution, and the broader native acceptance roadmap remain incomplete.

## 1 Draft contracts

Implemented: creation, lookup, queries, content, titles, dates, coordinates,
tags, flags, organization states, syntax, versions, logs, and templates.
Specific tests cover tag normalization, identity, date and folder queries,
UTF-16 edits, storage failure rollback, revisions, and shared draft references.
Recorded native checks cover metadata, text, selection, saving, and Undo/Redo.

Pending:

- Finish evidence for each included member, defaults, returns, and errors.
- Complete syntax-specific tasks, multiple states, markers, and links.
- Finish grammar and recent-tag contracts, Mustache, and custom template tags.
- Complete native version and execution-history access checks.
- Verify permalinks from another app.
- Resolve the readonly `Draft.tags` reference versus retained direct assignment.
- Close `Draft.query` reference dependencies and parent/descendant tag behavior.
- Compare out-of-range `Draft.insert` with Drafts when Pro access is available.

## 2 Editor contracts

Implemented: text and selection APIs, load/new/save synchronization, native
Undo/Redo, focus, recent drafts, navigation, tasks, and separate advanced find.
Tests cover UTF-16, Unicode, line boundaries, immediate visible edits, and Undo.
The preferred find checkbox was verified with both Cmd-F interfaces.

Pending:

- Finish per-member properties, activation, navigation, recent-draft evidence,
  and `editor.draft` contracts.
- Connect the preferred tab string to each syntax configuration.
- Finish tasks, markers, links, Arrange, and their variants.
- Finish advanced find options, result navigation, replacement, cancellation,
  and native-find coexistence.
- Finish negative dictation/transcription cases and text preservation.
- Keep the Mac scan-document unavailability evidence separate from file OCR.

## 3 Workspace contracts

Implemented: saved filters, exclusions, dates, folder views, flags, sorting,
access dates, presentation options, groups, default workspace, and installation
URL decoding. Tests cover persistence, unknown fields, missing references,
query order, and several visible-window applications.

Pending:

- Finish each name, date, link, query, and per-folder sorting contract.
- Complete unknown access-date and flags-first acceptance.
- Verify initial folder, groups, and themes by identity in actual windows.
- Compare query results with visible rows after restart and backup restore.
- Verify external installation links and missing references without partial changes.
- Complete shared theme persistence needed by workspace application.
- Compare `QueryDate.create()` in Drafts; the archived signature contradicts
  its description. Keep this comparison blocked, not accepted.

## 4 Syntax prompts and core steps

Implemented: built-in syntax selection, custom definitions, validation and
storage, prompt controls and response transport, Create Draft, and Configure
Window. Version and prompt validation failures have targeted regressions.

Pending:

- Finish official custom grammar features and multiple task states.
- Verify syntax install, replacement, external files, reload, URLs, and built-in
  name collisions. Preserve unknown fields.
- Finish all included Create Draft and Configure Window variants.
- Finish Prompt and SelectPrompt constructor/factory, defaults, controls,
  subtitles, icons, help, focus, scrolling, and native presentation.
- Verify cancel, Escape, close, and non-cancelable prompts.
- Keep unavailable reference comparisons pending without Drafts Pro.

## 5 Actions engine

Implemented: legacy adapters and runAsync, a serial JavaScript worker,
execution identity, current step, cancellation requests, and a final report.
The report distinguishes asynchronous-script timeout. A library gate prevents
concurrent runs. Step epochs isolate script completion and timers. Included
steps share context; enabled unknown steps fail before execution. Imported
unknown or disabled steps remain stored.

Tests cover original actions, promise rejection, duplicate completion, stale
step timers, cancellation, timeout, queues, circular includes, and success
metadata. New session tests cover final report identity and cancellation while
preserving completed host effects.

Pending:

- Finish native acceptance of the migrated UI, URL, and App Intent entry points.
- Remove remaining synchronous waits in native capability adapters. The new
  worker script wait uses continuations and scheduled timer events.
- Complete run/step callback tokens, late callbacks, reentry, simultaneous
  windows, and cancellation/timeout from every entry.
- Complete native include and remaining context/queue acceptance. UUID and
  templated-name resolution now have automatic tests on both execution routes.
- Close the fourteen required engine evidence records. The strict auditor
  rejects missing records.

## 6 Integrations and automation

Implemented paths include URLs, App Intents, HTTP, XML-RPC, local files,
bookmarks, Mustache, Markdown, HTML conversion and interactive preview,
Shortcuts, AppleScript, shell, Mail, Messages, Calendar, Reminders, speech,
location, and Apple models. Coverage and native availability vary.

Recent work connects Markdown preferences to previews, HTML Preview steps,
Action templates, file names/folders, and scripting `processTemplate`. HTML
paste has Unicode, selection, Undo/Redo, tag-name, and clipboard regressions.
Bookmark creation and Forget were verified with a neutral folder. Battery and
positive dictation/transcription evidence remain valid.

Pending:

- Finish async URL/Intent results, parameters, destinations, and real callbacks.
- Complete local HTTP/XML-RPC server cases, dates, binary data, malformed
  responses, network errors, cancellation, and timeout.
- Finish bookmark restart, actual Action access, stale/denied permissions,
  iCloud Drive, and Mustache folder contracts.
- Finish HTML structures/options, native paste from another app, preview data,
  and cancellation. The regex converter is not complete HTML parity.
- Finish native acceptance for Mail, Messages, Calendar, Reminders, Shortcuts,
  AppleScript, shell, location, and Apple models.
- Separate permission denial, cancellation, system unavailability, and defects.
- Require an authorized recipient and content before sending any real message.

## 7 Action inspector and organization

Implemented: step editing, configuration values, description/options, shortcuts,
groups, sections, ordering, visibility fields, confirmation, notifications, and
success tags/flags. Shortcut validation is shared. Original scripts are intact.

Pending:

- Complete imported options, visual icon selection, step/platform editors,
  and uniform order/visibility in every access.
- Verify edit copies, cancel, atomic import, confirmation, and result effects.
- Finish create/edit/duplicate/move/reorder/delete acceptance for actions/groups.
- Finish export/backup/restore, retained unknown fields, shortcut conflicts,
  and visual inspector parity.

## 8 Preferences and personalization

Implemented: fonts/Nerd Fonts, size, spacing, margins, maximum width, typewriter
scrolling, shortcuts, themes, and workspace management. Settings has General,
iCloud, Bookmarks, Markdown, HTML, Editor, and Shortcuts categories.
General includes appearance, menu bar visibility, capture timeout, preferred
find, launch-at-login registration, initial-window policy, three global shortcut
recorders, and After Success move navigation. Current workspace snapshots preserve advanced filters, tag presence,
unknown fields, and per-folder order on save and application. Missing references
are rejected before Save Current persists. Native missing-reference and failed
save checks remain pending.
The app menu has Editor Settings, Library Summary, and library-wide Empty
Trash with confirmation, including when no command window exists.

Pending:

- Verify launch-at-login on a service-capable installation, physical global-key
  delivery, and the remaining startup/restoration variants. Initial-window policy,
  recording, persistence, and the recorded action navigation paths passed their
  specific checks. Finish the other included Settings categories and native
  appearance/geometry comparisons.
- Complete individual Markdown options, escaped line breaks, live changes, and
  visual/click checks for reference-help controls.
- Verify workspace date/flag/per-folder sort controls in native use. They are
  implemented. Group and theme selectors are also implemented. Their saved
  selections and Cancel passed a native QA check; full application/restart
  coverage and visual parity remain open.
- Shared themes now use generic library records with stable identities and
  optional backup data. Local definitions migrate once per device and library.
  Native create/save/edit-cancel/restart/render and selection/Undo passed in QA.
  Native backup record recovery passed. Restored-theme rendering, legacy
  migration, and Mac+VM sync remain pending.
- Drafts theme file import now validates and preserves complete source, with
  review and explicit rendering limits. Native file import/save/replace/cancel
  passed. Exact scope rendering now has background tests for Markdown/custom
  syntax. Verify it natively and complete other syntax/interface coverage. Verify MultiMarkdown/TaskPaper in all accesses.
- Verify restart, backup, selection, content, and Undo after configuration changes.
- Keep local device preferences separate from shared library definitions.

## 9 Main window capture and search

Implemented: native split panels, tracked toolbar separators, tabs, draft rows,
tag capsules, flags, footer statistics, action panels, menu bar commands,
swipe Archive/Trash, batch/context operations, and Merge with Archive default.
Capture has its own persistent buffer/window. Quick Search is independent from
list filters. Two macOS Services have implementations and recorded native checks.

Pending:

- Complete paired visual captures at 1033 × 734 and 1200 × 800 points; review
  850 × 600. Cover themes, activation, search, panels, tabs, and selection.
- Finish typography, icon, material, action-panel, toolbar, and tab parity.
- Finish one-point alignment measurements and Dock/Finder/app-switcher icon checks.
- Repeat rapid transitions, Reduce Motion, resize, focus, Undo, overflow,
  swipe, and VM redraw checks. Preserve chosen widths.
- Finish status-menu icons/separators/recents, empty clipboard, no-window Empty
  Trash cancellation, Quit with edits, and Merge integration.
- Finish Services/capture/search from another app, without a main window, with
  multiple windows, after restart, and after save failures.
- Update the habitual app only after the required regressions pass.

Computer Use can read Drafts and QA Settings. The earlier native-pipe failure
recovered; later Settings interactions passed their recorded checks. A future
observation failure must still be checked against the actual process state.

## 10 Data sync and personal distribution

Implemented: Core Data storage, compatible backup import, revisions, conflict
copies, action groups/syntax backup, local builds, and development-signed builds.
The main CloudKit container passed initial download, creation, and edit exchange
between the Mac and UTM VM. The access-date/content conflict fix was retested.
See [iCloud evidence](research/icloud-acceptance-2026-10-19.json).

Pending:

- Shared themes and execution history are included in compatible backups with
  rollback tests. Native merge recovery and restart passed for the recorded
  fixture. Complete the remaining conflict, syntax, group, and failure cases.
- Repeat restore/migration and unknown-field checks for all new fields.
- Repeat the broad main-container matrix with both clients connected: metadata,
  revisions, actions/groups/order, workspaces, syntax, themes, Trash/Restore,
  access dates, and concurrent text variants.
- Verify a signed update with a different executable and existing library.
- Verify effective team and profiles on both recipients.

Offline checks remain postponed. Two physical Macs are additional coverage.
Developer ID, notarization, and public distribution are outside this delivery.

## 11 Audit performance and final acceptance

Pending:

- Review all unclassified members and resolve included partial contracts.
- Complete exact signatures, defaults, returns, errors, and specific evidence
  for all included objects and 25 step types. Preserve manual evidence.
- Run strict core and global checks. A normal structural check is not parity.
- Measure search/selection/scrolling with 10,000 drafts; measure editing,
  search/selection/Undo/save with 100,000 characters. Record typical/max times,
  hardware, build, data, and storage. Fix stalls and text loss.
- Complete integrated native runs and local/signed builds.
- Preserve explicit Pro, permission, hardware, and postponed-check limitations.

## Repository cleanup and next session

- Split app coordination, delegate, commands, and Settings out of the scene file.
- Removed three tests that repeated a toolbar identifier array. Native layout,
  animation, state, data, and Actions regressions remain.
- Removed two redundant test transcripts, four old root build logs, and generated
  caches. Kept app products, signed packages, frozen references, and VM evidence.
- Removed obsolete ignore-template sections and duplicate/stale README claims.
- Updated the glossary for merge sources, capture, backup contents, and execution.
- Removed the session evidence directory at the user's request. Current results
  remain summarized here; removed artifacts are not available for reinspection.

Next implementation priority requested by the user: the Actions engine. Start
from its initial session; the worker and real async entry do not exist yet.
Repository organization is a separate task and does not close engine contracts.

Both apps were reset locally without a recovery copy after explicit confirmation.
Drafts shared data and its app preferences were deleted through Finder. Draftly's
local store, 34 temporary QA libraries, and 14 preference domains were removed.
Both apps opened with 0 drafts and empty editors. Drafts iCloud is off; the new
local Draftly build has no CloudKit container. Remote iCloud data was not reset.
The new local Draftly is `.build/xcode/Build/Products/Debug/Draftly.app`.
All former screenshots, the `docs/research/evidence` directory, three local build
evidence directories, and ten additional generated logs were removed on request.
Generate new native captures for future acceptance. Historical validation text
is retained as a summary, not as an inspectable artifact.

Excluded: mobile platforms, widgets, MCP, Chat Console, third-party AI/connectors,
and Mail Drop. Native Apple models remain in the Mac scope.


## Version control review 19 October 2026

The initial review found `main` equal to `origin/main` and an empty index.
The user then authorized commits and push. The changes are split by behavior
below. Use Git history and remote tracking status for the publication state.

### Include in commits

- Production Swift and JavaScript changes, including the new source files.
- Their contract and regression tests, including the five unchanged fixtures.
- `Configuration/Info.plist` Services metadata, `Package.swift`, and the generated
  Xcode project. Keep the project source references aligned with added app files.
- README, glossary, this status, validation summaries, and compatibility matrices.
- The benchmark tool and frozen API reference needed by the auditor.

Shared files were staged by change. Each staged source snapshot was copied to
a temporary build directory. Swift tests compiled the app and checked each
change before its commit. The final run covers the complete change set.

| Commit | Scope |
| --- | --- |
| `fix(core): enforce draft editor and workspace contracts` | Identity, focus, prompt responses, version rollback, installation decoder, and member tests |
| `fix(ui): stabilize panels and align draft presentation` | Split transitions, row measures, toolbar state, redraw, footer statistics, and visual matrix |
| `refactor(app): separate lifecycle commands and settings` | Source extraction and generated project references |
| `feat(markdown): apply preferences to previews and templates` | Renderer settings and template integration with contract tests |
| `feat(capture): add native capture services and preserve pending edits` | Services registration, capture routing, and failure handling |
| `feat(settings): add preferences and library commands` | Settings pages, app menu, bookmarks, HTML paste, and shared Trash command |
| `feat(actions): add execution sessions and final reports` | Initial session, legacy adapters, cancellation, timeout, and reentry tests |
| `chore(repo): clean artifacts and record implementation status` | Ignore rules, package warnings, glossary, README, and status summaries |

The first extraction-only candidate exposed failures already covered by pending
identity and redraw fixes. It was not committed. The corrections precede the
extraction in the final history. Full asynchronous execution remains pending.

### Keep local or ignored

- `.build`, app bundles, archives, generated caches, and logs.
- Screenshots and regenerated session evidence.
- `Configuration/Signing.xcconfig`, profiles, certificates, private keys, and env files.
- User databases, captures, exports, backups, and machine preferences.
- Xcode user state, Python cache, and the local handoff.

Keep `CLAUDE.md` and `.claude` as tracked symlinks to their existing sources.
The signing example and public app/container identifiers may stay tracked.
The tracked-file scan found no private keys, GitHub tokens, AWS access keys, or
matching device identifiers. No signing profile, private signing config,
database, or log is tracked. This targeted scan is not a full security audit.

### Push gate

Push only the tested commits, after reviewing their staged diff and running the
checks in README. A complete Mac parity claim is not justified. Engine async
work, native acceptance, and strict gates remain open. No history rewrite or
force push is needed for the current branch state.

## Async native input delivery — 20 October 2026

The async host now covers prompts and confirmation, file transcription, calendar
editing and creation, and Apple model responses. Model tools reject closed
requests and discarded sessions. Legacy adapters remain compatible. Live
dictation and the remaining synchronous native adapters still need review.

The final background run passed 260 app tests and 313 core tests. The unsigned
Xcode build and normal matrix check passed. The strict engine gate remains open
with 120 evidence diagnostics. Real acceptance for the new dialogs, transcription,
EventKit persistence, and model tools is pending. See docs/validation.md for
specific cases. The full Mac plan remains open.


## Current engine delivery — 20 October 2026

Dictation and AppleScript use cancellable native adapters in the async route.
AppleScript preserves missing values and native record fields. Neutral real QA
verified AppleScript success and cancellation, prompt keyboard behavior, selector
filtering, and URL confirmation cancellation. A launcher-only Debug refresh was
invalid; all accepted new checks were repeated with the complete code image.

The final run passed 288 app tests and 322 core tests. The unsigned build and normal
matrix check passed. The strict engine gate has 44 evidence diagnostics. All 14
engine records remain partial, with specific pending native checks and limits.
No API member classification changed. Real dictation and the remaining native
capability checks are pending. The full Mac plan remains open.

## Current native wait delivery — 20 October 2026

Interactive HTML, file panels, bookmarks, and composition use async host adapters.
Native interruptions and expired replies stop later effects. Shared file/message
payloads preserve the legacy route. Real QA passed embedded HTML data and
cancellation, Save cancellation, and exact Unicode export. Real Mail/Messages,
bookmark persistence, standalone HTML, and other native variants remain pending.
Composition options that the adapter cannot implement fail explicitly; they stay
compatibility limits. Printing, arrangement, and sharing outcomes still need work.

The final run passed 315 app tests, 330 core tests, and 32 Python tooling tests.
The unsigned build and normal matrix check passed. Strict engine acceptance is
open with 42 diagnostics; all 14 engine records remain partial. API member
classifications are unchanged. See docs/validation.md for exact evidence.

The engine unknown disabled imports contract has passed its specific automatic
and native checks. Thirteen engine records remain partial; strict engine parity
reports 39 diagnostics. This is separate from the 562-member API inventory. See
the latest validation entry for the independent window-close control and payload
round trip.

The current separator delivery adds shared non-executable presentation and
retains management controls. Native QA checked the list heading, horizontal
line, edit/save order, and exclusion from search. Bar/menu/picker and native
backup recovery checks remain pending. The separator contract stays partial.
Inclusion and queue tests also found and fixed retained pending queue state in
the legacy failure/cancellation route. Final checks passed 388 app tests, 361
core tests, Python32, and the unsigned build. Matrix structure is valid; strict
engine parity still reports 39 diagnostics. See the latest validation entries.

Native follow-up checked separator order after restart, the editing bar divider,
and absence of an executable separator in the Actions menu. URL queue cancellation
kept the completed child edit in Inbox, stopped later work, and delivered one
observed cancel callback without success parameters. Native error/timeout,
separate targets, picker, and backup recovery checks remain open. The matrix
records partial acceptance and specific executed regression tests.

Native URL queue failure and the production 120-second timeout also passed.
Both kept the completed child text in Inbox, stopped later steps/actions and
Archive, recorded Error, and delivered one observed matching error callback
without success parameters. Separate targets and remaining native entry points
still need acceptance. The queue record remains partial.

Separate-source/target cancellation passed through a URL using the matching
visible editor. Both drafts kept their own completed text in Inbox. The editor
finished on the target and one cancel callback was observed. Separate-target
error/timeout and remaining native entry points are still pending.

Native static and dynamic inclusion cycle checks passed. Static cycles preserve
the original text; dynamic cycles retain earlier effects and stop the cyclic
subtree, tail, and success disposition. The engine cycle safety contract is now
complete, with its 50/51 depth boundary documented as a Draftly policy. Two
engine records are complete and twelve remain partial. Strict parity reports
36 diagnostics; entry-point equivalence and full Mac acceptance remain open.

Native URL CPU deadline acceptance passed with responsive filters and retained
text. Direct UI and Intent variants remain pending. New async-limit cases pass,
but an unreturned rejected promise still becomes timeout. Its two error-report
assertions are recorded known issues; this is not accepted promise parity.

The subsequent correction resolves those rejection issues. The runtime observes
engine-level unhandled rejections, including intrinsic async promises; caught
rejections still succeed. Native URL checks passed for all three cases. A new
per-worker authority also rejects unknown, altered, and repeated host requests
before effects. Full checks passed 388 app and 373 core tests without known
issues, plus the unsigned build. Remaining native contracts stay partial.

CPU task cancellation and cross-step promise/timer regression cases passed.
Native overlap with two independent windows and URLs also passed: the second
request returned busy without edits, while the owner completed successfully.
Intent overlap and the other required native variants remain pending.

The strict evidence check now rejects complete records backed by directly
disabled or known-issue tests and missing method references. Explicit test files
support suites in shared source files. Python37 and matrix structure passed;
strict engine acceptance remains open with 36 diagnostics. The user-authorized
two disposable Shortcuts were deleted and their absence was verified.

Native inclusion by UUID survived a real inspector rename. Template-name
inclusion resolved the renamed action and both calls shared one global. The
shared-inclusion record stays partial: configuration precedence and native first-use configuration acceptance remain
unresolved. Both runners now prompt for required first-use values, distinguish
confirmation from imported defaults, and save accepted values atomically.
Cancellation, storage failure, concurrent edits, and included-action ordering
have specific background tests. The regression run passed 388 app and 390 core
tests. Native configuration checks remain pending.


Native first-use text configuration passed: Escape retained the source, Unicode
acceptance reached the editor, and confirmation survived a restart. Included
static cancellation kept the original text; dynamic cancellation kept the prior
root effect. History confirmed the final results. Other field types, new required
fields, and configuration precedence remain pending. The record stays partial.


Native Boolean/number configuration and new-required-field checks passed. Invalid
numeric input was rejected without losing the checkbox or text. Acceptance kept
false and zero as typed JavaScript values. An imported revision retained prior
confirmation and prompted only for its added field. Configuration precedence
remains unresolved.


Completion and timer isolation now has native URL acceptance for old handles,
removed old timers, current-step waiting, duplicate completion, and failure
precedence. The specific automatic cases passed in a focused five-suite run.
That engine record is complete. Returned rejection also passed natively; its
shared timeout record remains partial. Entry-point acceptance is still open.


Current-image direct UI CPU timeout and native URL 120-second queued timeout
passed. Filters stayed responsive during CPU work. Both failures kept prior text
in Inbox and stopped later steps/Archive. The queued timeout delivered exactly
one error callback without success parameters. The new actual-worker automation
boundary case and existing context cases passed (nine methods). App Intent and
separate-target variants remain pending; no broader closure is claimed.


Action installation by URL now saves the decoded set atomically. Storage failure
rolls back replacements and new actions. Four focused installation cases, both
URL target regressions, and the unsigned Debug build passed. Native failure
injection was not performed. Existing import compatibility evidence remains
scoped to its recorded checks.


The actual RunDraftActionIntent.perform now has isolated background tests for
success, errors, busy reservation, CPU/async deadlines, and cancellation. The full
run passed 401 app and 391 core methods. Xcode metadata extraction passed without
new visible parameters. Native Shortcut dispatch remains pending. Review found a
separate headless-owner overlap gap before pending saves; it is not accepted yet.


The headless-owner overlap gap is fixed. Canonical library exclusion is checked
before pending saves or selection changes in automation and single/batch window
actions. A real overlapping intent regression failed before the correction and
now passes across five accesses. The final full run passed 402 app and 391 core
methods. Native system delivery of these new cases remains pending.


Native Shortcuts now verifies success, production CPU timeout, and a 120-second
queued timeout on a different note. Mixed Intent/URL overlap passed in both
directions, including two windows and an owner without a matching editor. The
synchronous-deadline and process-local exclusion records are complete. Remaining
cancellation, source-close, callback, and capability variants stay open.


Worker runtime operations now enforce serial queue ownership. A scalar probe and
two actual worker cases verify host suspension, timer success, cancellation, and
explicit close/release off MainActor. Full regression: 402 app and 392 core methods;
unsigned Debug build passed. Native acceptance of the assertion build remains
pending. The worker record is still partial.


Native theme link acceptance now covers the configured green underline and
disabling Link Mode with Unicode selection intact. Exact Drafts precedence and
other theme interface mappings remain open. General Settings was inspected in
Drafts: launch-at-login and main-window-at-launch controls exist. Their Draftly
implementation and lifecycle acceptance remain pending. See validation for the
observed controls and limits. Workspaces, Settings, and personalization are not
closed.


Launch at login now uses the system service and exposes approval/errors. Three
isolated contract methods, full regression (419 app and 416 core), and the
unsigned build passed. QA showed the system notFound/unavailable path. Real
registration and login acceptance remain pending. Main-window launch policy and
configurable global shortcuts are not implemented by this change.


Show main window at launch is implemented with local persistence and scene
suppression/restoration policy. Early explicit window requests wait for the
scene opener. Native QA passed disabled/enabled startup, warm and cold URL
selection, and capture without the main window. Full regression passed 421 app
and 416 core methods. Dock reopen and other installation/restoration variants
remain pending. Configurable global shortcuts are still next.


General now exposes three global shortcut recorders with local persistence,
shared conflicts, clearing, and Carbon registration. Native recording, conflict
rejection, restart persistence, and capture inside QA passed. The attempted
synthetic event from another app did not trigger capture; global delivery stays
unverified with cause unresolved. See validation. Full regression passed 422 app
and 419 core methods before the two final focused corrections; final focused
checks and build passed. This does not close global shortcut acceptance.


Global hotkey registration now uses fresh identities. Focused tests verify
rejection of stale events and identity exhaustion; the build passed. Physical
global delivery remains pending. Drafts After Success navigation was inspected:
Create New Draft and Open Next Draft are the two choices. Draftly integration
and behavior acceptance remain open.


After Success move navigation is connected to General, single-window execution,
and single context commands. Automation retains the processed draft identity
separately from editor navigation. Multiple-target execution retains its agreed
last processed draft. Eight contract methods, the full regression (432 app and
419 core), and the unsigned build passed. Native interaction and exact Drafts
comparison remain open; see validation for the fallback and batch policies.


Native After Success navigation now passes Actions-menu Archive to scratch,
Trash to the next visible draft, original archived text retention, and preference
persistence after restart. The preference was restored to Create New Draft.
Action-panel, URL presentation, Undo, and exact Drafts acceptance remain open.
The neutral action fixture is saved under scripts/fixtures for repeat runs.


Native action navigation also passed from the action panel and a confirmed URL
on a visible owner. The URL left the scratch selected and delivered one success
callback. Undo/Redo in that scratch and the original archived text passed their
checks. Older Undo stack retention, headless variants, list-end behavior, exact
Drafts comparison, and the physical global-key check remain pending.


Execution history now joins themes in compatible version 1 backups. Six specific
methods and the full regression (432 app and 425 core) passed. The unsigned build
passed. Native recovery and connected synchronization remain pending.


Native Import now routes action and note files through one transaction per file.
It also preserves distinct texts that share an incoming note ID. Five specific
methods, the full regression (432 app and 430 core), and the unsigned build
passed. Native recovery and failure injection remain pending. Multi-file
selection has a per-file boundary; earlier successful files are retained.


Native backup recovery passed export, import into a separate local library,
restart, and export again. All source records matched by identity and full data,
including 75 execution records. One unrelated neutral note/revision from a
selection mistake remained as an explicit destination extra. Syntax/group arrays
were empty. This does not close conflict, failure, or connected-sync acceptance.


Native content-conflict recovery passed in Recovery QA. Both texts survived.
The recovered revision and execution use the copied note identity; the existing
execution still uses the edited original. Export comparison verified the graph.
Other conflict variants, native storage failure, syntax/groups, and connected
sync remain pending.


Markdown preview now respects processor line breaks instead of forcing paragraph
whitespace preservation. An offscreen WebKit contract failed before the fix and
passes after it. Full regression passed 435 app methods and 430 core methods;
the unsigned build passed. Live Settings refresh and Drafts comparison remain
pending after a Computer Use connection failure. Global physical-key delivery
also awaits the user's result. The full Mac plan remains open.


A disk-backed conflict-restore failure/retry contract passed with the other six
history-backup methods. Failure preserves the complete graph across reopening;
retry commits one recovered graph. Repeated successful conflict import remains
open: current restore assigns a fresh recovery identity on each conflict.


Repeated successful conflict import now reuses a stable recovery graph. It
preserves a newer access date, keeps edited recoveries, and does not merge
unrelated notes by content. Two new contracts and all nine history-backup
methods pass. Full regression passed 435 app and 433 core methods; the unsigned
build passed. Native and connected-sync checks remain pending. Old random
recovery identities are retained without content-only migration.


ActionLog now enforces readonly bridge fields and maps known status spellings
without case sensitivity. Two specific contracts failed before the fixes and
pass after them. Full regression passed 435 app and 435 core methods; unsigned
build and matrix structure passed. Draft.actionLogs has specific evidence for
filtering, order, types, dates, empty history, and independent arrays. Native
acceptance and the remaining ActionLog paths stay partial.


Action log deletion now rolls back and propagates storage failures. Legacy and
worker tests cover failure, retry, void return, unrelated history, and disk reopen.
Action relation tests cover rename, deletion, and same-name replacement. Full
regression passed 435 app and 437 core methods; build and matrix structure passed.
Required native and remaining member variants keep these contracts partial.


Template tags now preserve names that overlap JavaScript prototype properties
through both renderers and later steps. Three specific methods pass, including
legacy and worker cases. Full regression passed 435 app and 440 core methods;
build and matrix structure passed. Template members remain partial. Computer
Use briefly reconnected but input failed again; native acceptance stays open.


Strict audit now validates historical additionalAutomatedTests as well as
supportingTests and reports malformed collections without a crash. All 38
Python tooling tests pass; matrix structure has zero errors. Strict core remains
at 800 diagnostics and engine at 27. Neither gate is accepted.


Draft.find now excludes inherited JavaScript cache keys. The extended existing
contract passes on legacy and worker routes after failing on both before the fix.
Metadata36, full app435/core440, and unsigned build passed. Native comparison
remains separate.


Workspace scripting now retains manual order, tagged filtering, native list
options, and non-API metadata. Four methods on both runners cover query, save,
application adapter, installation, backup, defaults, precedence, and invalid input.
Full app435/core444 and unsigned build passed. Create/query/update are partial
again until affected native checks are repeated; previous evidence is preserved.
Strict core has 809 diagnostics. The full plan remains open.


Next/previous editor navigation now retains the prior cached Draft selection.
The two extended methods pass all four legacy/worker cases after failing before
the fix. Full app435/core444, unsigned build, and matrix structure passed. Native
selection/focus acceptance and remaining error variants stay pending.


All five library deletion entry points now share rollback and error propagation.
Disk-backed action/workspace cases cover failure, unrelated save, reopen, and
retry. Full app435/core445 and unsigned build passed. Native acceptance currently
requires the user to unlock the Mac; Computer Use also has recorded service
assertions. These do not establish a Draftly failure.


Mustache rendering now stays in the action context instead of creating a host
context on MainActor. The async route therefore uses its worker and script
deadline. Two worker contracts and existing template/tag cases pass. Full
app435/core447, unsigned build, and matrix structure passed. Native and remaining
engine/Mustache acceptance stay partial.


Directory Mustache rendering now retains prototype-named files and partials.
Instance factory methods coexist with the original static calls. The extended
directory contract passes both runners, including defaults, escaping, missing
files, and traversal rejection. Full app435/core447 and unsigned build passed.
Three audited members remain partial pending their specific native checks.


XML-RPC now uses awaited HTTP on the async route instead of MainActor RunLoop
polling. Three methods cover wire conversion, actual JS response, fault/error
values, injected transport cancellation/timeout, and gate cleanup. Full
app435/core450, unsigned build, and matrix structure passed. Real server and
native XML-RPC acceptance remain pending; the member is partial.


Float on Top now changes from outline to fill with its window state. Three
toolbar tests and the unsigned build passed. Computer Use confirmed both states
in refreshed Engine QA. App and menu icons now share generated notes-and-pencil
geometry. Resource previews passed inspection; Dock/Finder/menu-bar acceptance
remains open. See the latest validation sections.


XML-RPC CDATA coverage passed seven focused tests against the unchanged parser.
The earlier loss claim was an inference that runtime checks did not confirm.
Params and error now have specific partial evidence. Real transport character
sets, server/native acceptance, grammar, and date/binary mapping remain open.


XML-RPC now rejects duplicate payload blocks, extra param values, and multiple
types in a value. Five malformed cases reproduced silent acceptance before the
fix. Full app436/core453, unsigned build, and matrix structure passed. This is
a bounded grammar correction; XML-RPC and the full Mac plan remain partial.


XML-RPC now has real loopback HTTP coverage for request bytes, Unicode/CDATA,
faults, and invalid responses. Full app436/core454 and matrix checks passed.
Native automation, date/binary mapping, transport character sets, and remaining
grammar stay open. The test does not close the full integration.


XML-RPC fault fields now reject missing or incorrect types without inventing a
fault code. Four red cases and a typed JavaScript fault check cover the change.
Full app436/core455, unsigned build, and matrix structure passed. Three response
fields now have specific partial evidence; full integration acceptance is open.


Real loopback XML-RPC cancellation now has an error-envelope check and server
confirmation of TCP disconnect. Full app436/core456 and matrix checks passed.
This is transport evidence, not native UI cancellation acceptance.


Current Engine QA passed native action-list checks for discarded, intrinsic,
and caught promise rejection. Earlier text survived failure; later insertion
and archive did not run. History showed two errors and one success. Other
entry-point, timeout, and cancellation variants remain pending.


Engine QA action-list acceptance now includes returned promise rejection and
the production 120-second async wait timeout. History confirmed both errors.
Panels responded during the wait; completed writes and Inbox state survived.
A subsequent action succeeded. Other entry points and CPU-bound responsiveness
remain unaccepted.


Actions now exposes Cancel Running Action for the current window. Automatic
checks and native menu/history checks passed, including a later successful run.
Full app437/core456 and unsigned build passed. Other menu action availability
while busy and remaining native cancellation variants are still open.


Action entry controls now share the current-window availability rule, including
the pending phase. Menu and palette behavior passed native busy/cancel checks.
Five focused tests and the unsigned build passed. Cross-window busy presentation
and native list/bar disabled appearance remain pending.


Library busy state now reaches every window from the execution gate, including
new windows. Native two-window menu/ownership/recovery checks passed. Automatic
checks also cover an independent library. Full app437/core456 and unsigned build
passed. Remaining native entry-point and presentation checks stay open.


Current QA passed native CPU-loop responsiveness and deadline checks. A panel
transition completed while Cancel remained enabled and runs were disabled. Both
runs recorded timeout without tail or archive effects. CPU cancellation remains
unaccepted: the attempted cancel lost to the deadline.


Native CPU menu cancellation now passed on current QA: enabled Cancel was
observed during the loop, history recorded Cancelled, and a later action
succeeded. This does not claim instant interruption or close other native
worker/cancellation variants.


Current QA passed Prompt and SelectPrompt accept/cancel through the worker
bridge. Unicode, discarded field edits, subtitle search, selected identity,
and final history status were checked. Other options and interruption paths
remain pending; this does not close these APIs or the engine.


Failed executions now retain prior script console output in stored history.
Both runners, context.fail/throw/cancel, repeated Unicode lines, multiline text,
and custom cancellation reasons passed tests. Native history output passed.
Full app437/core457 and final unsigned build passed. Old lost output cannot
be recovered; no history format or existing record is changed.


Context.cancel now preserves omitted-message semantics on the async path. Both
runners pass exact Unicode reason, undefined return, current-script completion,
quiet cancellation, and stop/disposition tests. Native history defaults passed.
Full app437/core458 plus final focused checks and unsigned build passed. Other
native notification and script-continuation variants stay pending.


Context.cancel has complete member evidence for the frozen valid-input contract.
Native current-script continuation, undefined return, stop/disposition, reason,
and imported notification settings passed. Both runner routes and quiet
notification behavior have specific automatic checks. Other Context, callback,
Workspace, engine, and global acceptance remain pending.


The application icon and menu template now share a simpler stacked-sheet mark.
Asset generation, small-size render inspection, and the unsigned build passed.
Live Dock, Finder, and menu appearance still need verification for this revision.


No-wait callbacks now leave response collections and template tags unchanged.
Both runner routes pass four specific cases. Native script and step checks pass.
Full regression passed app437/core459; the unsigned build passed. Other callback
contracts remain pending.


Finder Get Info now confirms the new mark in the installed QA bundle. Live Dock
and menu-template inspection remain pending because their Computer Use targets
timed out. Other QA and Finder controls worked.


CallbackURL preserves prototype-named outgoing string parameters. Both runners
and a native action pass specific key, Unicode, return, and replacement checks.
Full regression passed app437/core460; the unsigned build passed. CallbackURL
remains partial for other value and error contracts.


Returned callback step data now preserves prototype-named keys. Four specific
cases pass across script/step and both runners. Full regression passed
app437/core461 and the unsigned build passed. Native response-key acceptance
is pending: the Mac locked before the helper update and fixture execution.
The engine strict gate still reports 27 diagnostics.


Shortcut no-wait now reaches the native process launch. Both runner routes pass
twelve response/option cases. Six background process tests cover input lifetime,
cleanup, default wait, cancellation after launch, timeout, and launch errors.
Full regression passed app443/core462; the unsigned build passed. Actual
Shortcuts no-wait acceptance stays pending while the Mac is locked.


Failed Shortcut processes now report an exit status when stderr has no useful
text. Unicode diagnostics stay exact. Six process cases and four script/step
cases pass; failures retain earlier effects and publish no successful result.
Full regression passed app444/core463; the unsigned build passed. Actual
Shortcuts and remaining status variants still need acceptance.


Included step ownership now has six specific cases across both runners and
name/UUID/template references, with nested native/script effects. The current
engine preserves owner, step, index, and execution identity. Seven focused
inclusion methods pass. No production change was needed. Configuration
precedence and native acceptance still keep the inclusion contract partial.


Native action, step, and presentation codecs now retain unknown flat JSON fields.
Single/array edit, repeated import, export, backup, restore, disabled execution,
and typed-collision cases pass. Full regression passed app444/core466; the
unsigned build passed. Installed-app acceptance is pending while the Mac is
locked. The import contract returns to partial for that newly exposed coverage
gap; earlier native foreign-payload evidence stays recorded.


Installed QA acceptance now passes returned callback keys and single native
action import/edit/restart/export with unknown fields. Wrapped and mixed native
imports remain open. Actual Shortcut no-wait script and step checks pass launch
return and response suppression. Waited execution reached timeout; two direct
CLI controls also stalled, although the Shortcut editor completed the fixture.
The cause is not established. Waited output is not accepted. See validation.md
for the isolated library, build identity, and exact check scope.


Grouped and mixed action imports now preserve each native entry instead of
remapping it as a Drafts export. Four specific cases pass; three reproduced the
loss before the fix. Full regression passed app444/core467 and the unsigned
build passed. Installed container acceptance remains pending.


Queued error/cancel effects on another draft now have four specific legacy/async
cases. They preserve completed effects, suppress success effects, stop the queue,
and select the matching callback. Full regression passed app444/core468. Native
entry coverage remains pending; no production change was needed.


Installed wrapped mixed import now passes execution, restart, and UI backup
export. The complete native action and foreign identity/payload/script survive.
Container inspector edits and native restoration remain separate acceptance.


Unknown disabled imports now passes its added native/container acceptance:
inspector edits survive restart, native restore recovers exact definitions,
and the restored action executes. That engine record is complete. Other engine
records remain partial. Library Organization editing needs a separate UI review.


Library Organization now exposes separate row buttons and opens the action
inspector locally. Native Edit, Cancel, Save, reopen, group Edit/Cancel, and Done
passed in QA. Ten relevant existing tests and the unsigned build passed. This
resolves the observed management access path, not full inspector parity.


Native UI close cancellation now passes at Command-W and the window close
button: history recorded Cancelled, completed writes remained in Inbox, no
tail or Archive ran, and a subsequent action succeeded. URL/Intent owner-close
and multiwindow acceptance remain open.


Native URL owner-close now returns one matching cancel callback and retains
completed text without success effects. A new offscreen test covers real
owner-notification filtering and observer removal. Full regression passed
app445/core468. Intent and multiwindow native acceptance remain pending.


Native two-window URL ownership passed: closing the non-owner kept callback
count zero; closing the owner produced one matching cancel callback. Intent
and same-draft ownership variants remain pending. A remaining-window menu
context observation needs source review before a fix is claimed.


Native App Intent owner-close now reports cancellation in Shortcuts, retains
completed draft text without success effects, and permits a subsequent successful
Intent. Existing actual-perform and lifetime/error tests pass. Same-draft
multiwindow ownership and other capability variants remain open.


A native delayed callback after cancellation no longer has acceptance pending
for the completed-next-action sequence: the helper confirmed its delayed URL
open, while history and editor retained Cancelled/Success and the next result.
Other late-response and native capability variants remain open.


Expired/new native callback sequencing now passes with distinct response values:
the cancelled request keeps Cancelled and the next accepts only fresh data.
The existing router cancellation test now rejects the old token during a new
pending request. Full regression passed app445/core468. Other capabilities
and entry variants remain open.


Imported editing bar labels and icon choices now affect rendering and survive
export and backup. Focused tests, the app build, and native QA button execution
passed. The full app suite passed 446 tests. The full core run did not finish
and was stopped; its cause remains open. Native inspector edit/cancel acceptance
and other imported presentation options remain pending.


A full regression recheck completed successfully: app446/core471. Matrix
structure passes. The prior core stall did not reproduce; its cause remains
unknown. This result replaces the incomplete run as the latest full test
evidence, but does not close native inspector acceptance or API parity.


Native inspector acceptance now passes for editing bar Label and Show Icon:
cancel discards both changes, save retains both, and the fixture was restored.
Other imported options and full inspector parity remain pending.


Imported action tint strings now affect list and editing bar colors and have
an inspector selector. Unknown names survive export and backup. Focused tests
and core471 passed. The full app run had two automation start-marker failures;
the isolated five-test recheck passed. Full-run cause and native palette
acceptance remain pending.


Automation cancellation tests now wait for a saved ready signal instead of
racing startup and a completion timer. Full regression passed app447/core471.
No production execution behavior changed. Native action tint acceptance is
still pending.


Native tint acceptance passes for imported green/orange rendering in list and
bar, plus inspector save/cancel and restoration. Drafts has an empty action
list and disabled creation/directory controls. Exact palette comparison and
remaining color/appearance cases stay pending.


Corrected required native import evidence fields using the existing verified
recovery record. All25 auditor tests pass. The engine strict gate reports27
diagnostics; other engine contracts remain partial. No new native acceptance
is claimed by this record correction.


Native separate-target UI queue failure and cancellation now pass: retained
writes, Inbox state, last-target editor, and stopped later work. Five queue
acceptance methods pass. URL/Intent queue variants remain pending.


Native URL cross-draft queued failure and cancellation now select one matching
error/cancel callback and retain completed writes without later work. App Intent
queue interruption and other callback variants remain pending.


Actual App Intent queued failure/cancellation now propagate the child result
through Shortcuts, retain completed writes in Inbox, and stop later work.
The QA shortcut parameters were restored. Remaining asynchronous interruption,
window-lifetime, and current-image timeout combinations stay pending.


Native URL owner-close cancellation now passes while a queued child waits on
a different draft: one cancel callback, retained Inbox writes, no later work.
Queued Intent owner-close and remaining timeout combinations stay pending.


Native queued Intent owner-close now passes with the exact source opened by
UUID and visible ownership confirmed. An initial non-owner run was stopped
separately and is not counted as owner-close acceptance. Retained writes and
Cancelled history passed. Current-image queued timeout combinations remain.


Current-image queued URL production timeout passed: one matching error callback,
retained Inbox writes, last-child editor, and no later queue work. Observation
times bracket the result; exact deadline delivery was not measured. UI/Intent
queued timeout checks on the current image remain pending.


Current-image queued Intent production timeout now passes: Shortcuts waited
for final error, retained Inbox writes and last-child editor passed, and no
later queue work appeared. An earlier interrupted run is not counted. The
current-image UI queued timeout remains pending.


The UI timeout attempt ended in cancellation after the editor changed to Q;
it is not accepted as timeout. Added queued-target coverage to the existing
owned-editor typing cancellation test. Full regression passed app447/core471.
The native UI production timeout check remains pending.


Backup restore now rejects duplicate IDs in all eight record collections before
writing. The regression failed before the fix and passes afterward without
changing the destination. Full app447/core471 and unsigned build pass. Native
import error presentation and sync acceptance remain pending. QA was not updated.


Native duplicate-draft backup rejection now passes on isolated QA imageca22fd59:
the error is visible and before/after full backup exports are byte-identical.
All existing notes, revisions, actions, and history stayed unchanged. Other
duplicate record kinds retain automatic coverage; sync remains separate.


Malformed recognized action/draft export JSON no longer falls back to a raw
text note through txt imports. Unclassified JSON text and unknown action fields
remain compatible. Full app447/core472, unsigned build, and matrix structure
pass. Native error presentation for this change remains pending.


Native txt imports of malformed recognized draft/action JSON now show their
specific errors. Both before/after full backups are byte-identical; no valid
prefix record or raw JSON note was added. QA is image13f8e82c. Broader import
and synchronization acceptance remain separate.


Multiple selected import files now prepare in isolation and commit changed
records once. Second-file and storage failures leave the destination unchanged;
disk reopen/retry and all eight backup collections have tests. Full regression
app447/core475 and unsigned build pass. Native multi-selection and staging
performance remain pending; QA was not updated.


Native multi-file picker acceptance passes on QA image785e0548: a rejected lot
leaves the full backup byte-identical; a valid mixed lot adds only its expected
action/note/revision. Restart preserves all record data by ID. Export array
order can change, so restart bytes are not identical. Performance and cloud
acceptance remain pending.


An optional release benchmark now measures10,000-note local imports, queries,
and100,000-character saves without visible windows or fixed thresholds. On
M2 Max/64 GiB, five fresh SQLite samples gave import median1092.570 ms and
maximum1296.808 ms; query median17.014 ms; save median196.603 ms. Data checks
and full app447/core475 pass. Native UI responsiveness and the remaining scale
acceptance stay pending. Reproduction and conditions are in validation.md.


### Imported action option gaps — 20 October 2026

Reviewed ActionImporter.decode against the five unchanged original action
fixtures. Foreign import explicitly maps description, tint, bar label/icon,
confirmation, assigned tags, disposition, shortcut, icon, and separator state.
It retains the full foreign object as rawPayload. Retention does not apply
these other settings:

| Field | Values present in original fixtures | Current behavior |
| --- | --- | --- |
| visibility | 2,480,2016 | Retained in rawPayload; presentation visibility stays at Draftly defaults. |
| notificationType | 0,1,2 | Retained; notifyOnSuccess/notifyOnError stay false. |
| backingAssignFlag | 0 | Retained when present; flagAfterSuccess stays nil. |
| groupDisposition | 0 | Retained; no imported group-disposition effect. |
| logLevel | 1,2 | Retained; no imported log-level policy. |
| groupUUID | Four UUIDs | Retained when present; import uses a group name or Imported. |
| backingPlatforms | 3 | Retained when present; no imported action platform restriction. |

Do not infer enum/bitmask meaning from these samples. Check the archived
reference and observable Drafts behavior before mapping values. Native Draftly
options use their typed persisted fields; this gap concerns foreign import.
Unknown numeric values must survive any later mapping. This audit does not
change the original scripts or claim completion of these imported options.


Notification import follow-up —20 October2026: notificationType0/1/2 now maps
to none/error/all, using the supplemental official wizard reference recorded
in validation. Original-fixture and both-runner tests pass. Raw unknown values
remain intact. Native notification delivery is still pending. Other foreign
option gaps in the preceding table remain open.


Log-level follow-up —20 October2026: foreign logLevel0/1/2 now controls none,
error-only, or complete execution history. Optional persistence preserves old
libraries and unknown integers. Both runners and the inspector use this
setting. Automatic and build evidence is in validation; native checks remain
pending. Other imported-option gaps remain open.

Native log-policy follow-up: six neutral actions confirmed None, Errors, All
history behavior. Inspector showed imported Errors and Cancel discarded a
change to None. Save/restart, timeout, and notification delivery remain pending.


Engine queue acceptance —20 October2026: queue cancellation is now complete.
Native UI production timeout passed after the earlier URL/Intent timeout and
interruption checks. Exact retained data and one root error were confirmed by
native export. Strict engine parity still has24 diagnostics across eight other
partial contracts. Full validation and remaining limitations are in the matrix.


Promise acceptance —20 October2026: promise rejection and asynchronous timeout
is complete for its named contracts. Direct returned-rejection URL now has one
correct error callback and retained Inbox text. Strict engine parity remains
open with21 diagnostics across seven other partial contracts.


Final callback acceptance —20 October2026: final callback selection is complete
for the named cases. Native merge and delayed-response checks passed. Strict
engine parity remains open with18 diagnostics across six partial contracts.


### Native awaited Shortcut responses — 20 October 2026

Inspected the existing Draftly QA Output — disposable shortcut. It contains
Wait 5 seconds, Text Native shortcut output café 🐼, and Stop and Output.
A direct editor run completed with that exact output. No shortcut was edited
or deleted. Then ran the existing QA Shortcut waited script and waited step
actions from Engine QA's Actions menu. Executable SHA256:
785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224.

The actions completed with measured fixture times 5238 ms and 5199 ms. Their
assertions checked the exact Unicode result, one callbackResponses entry,
and shortcut_result template tag. History showed Success for both actions.
The earlier native timeout remains part of the record; this run proves the
success path now worked with the existing shortcut, not why it stalled before.

A separate QA Shortcut callback control run recorded Cancelled. During that
run, a new draft with text So appeared without an agent edit. Its origin and
the cancellation trigger were not established. Do not use that run as callback
success or cancellation acceptance. The new draft was left unchanged. Engine
QA now has 10 drafts and no pending action. History was closed. The scratch draft
retains the exact text Shortcut waited step finished in 5199 ms café 🐼.

NativeProcessExecutorTests and ShortcutLaunchTests passed 15 tests. These use
local process fixtures; they do not open windows or invoke real Shortcuts.
Real native callback timeout and other permission/capability variants remain
pending. No screenshot or raw process log is tracked.


### Duplicate editor preflight writes — 20 October 2026

Found a preflight regression with two editors on the same draft. When the
dirty owner was flushed first, the clean duplicate wrote its old text back.
The owner then restored its pending text. The final result looked correct,
but the intermediate stale save could create revisions and sync changes.
A save spy reproduced Pending → Stored → Pending without any visible window.

Automation preflight now calls synchronizeStoredEditor before each flush and
once after all flushes. That existing method skips dirty editors. It refreshes
clean editors from current storage, so model enumeration order cannot cause
a clean duplicate to save its stale text. Pending edits still use flush and
retain the existing error path. This does not resolve simultaneous conflicting
dirty edits or change window selection policy.

Added cleanDuplicateEditorCannotOverwritePendingOwnerText with both owner
orders. The original code failed for owner-first order. The correction passed
both orders, retained Unicode text, used the selected owner's runner, and made
no old-content write. Focused automation and Intent suites passed 23 tests; the
full run passed 450 app and 480 core tests. Tests use in-memory libraries and do
not create or activate windows. Native two-window acceptance remains pending.

The unsigned local Xcode build passed. Matrix structure check passed with
zero errors. No installed QA app was replaced for this change.


### Native duplicate-window URL owner selection — 20 October 2026

Updated the stopped Visual QA app from the local build of 0b91f58. Kept its
Info.plist, local library, and ad-hoc signing type. Signature verification
passed. Executable SHA256:
87fb326b8af993eef9e2450d5f6156b9807203f97c86a8a2c457a2c8624d24fd.
Debug library SHA256:
58c64335164f32d5233b44db496a77267a5a6abd200adc6a19bce09b11115302.
No permission changed and CloudKit remained disabled.

The manual callback helper now has an explicit Engine QA/Visual QA selector.
It opens only the named installed app and checks the expected bundle identity
and DraftlyUITesting flag. Engine QA remains the default. The read-only window
monitor still targets Engine QA and its label now says so. Compiled the helper
and passed its window-inventory self-test before replacing its stopped copy.

Imported engine-window-owner-actions.json into Visual QA. Reused its single
neutral draft, UUID 2CD5AB10-6A3A-4E79-A2AF-33A4E4AC41DB. Set its text to
Alpha 🐼 Beta café Gamma and used Open in New Window. Both native windows
displayed that same draft. Window IDs were library-AppWindow-1 and library-AppWindow-2.

Selected Alpha in Window 1 while the duplicate had a different selection.
Sent a run URL with the exact UUID through the helper's Visual QA target and
confirmed Run Action. The helper received one success callback, selected=Alpha.
Then activated Window 2 through the native Window menu, confirmed its window ID,
and selected Gamma. The second URL run returned one success callback with
selected=Gamma. Both windows displayed the final text
Owner:Alpha 🐼 Beta café Owner:Gamma. No second note was created.

This accepts visible same-draft URL ownership in both activation orders and
content propagation between clean editors. It does not prove App Intent
selection, minimized-window fallback, or a timed pending edit before autosave.
The automated regression covers that preflight write boundary. Both QA windows
remain open on the one neutral draft; the helper has no pending reply timer.
No screenshot is tracked.


### Draft and Editor URL contract cases — 20 October 2026

Added DraftURLContractTests.fullCustomURLsAreReturnedAlongsideHTTPS for both
legacy and worker runners. It checks HTTPS with an escaped query, draftly://,
shortcuts://, tel:, and mailto: URLs. It checks exact order, duplicate
occurrences in an unsaved detached draft, unchanged editor reads, Unicode
surroundings, no matches, and empty content. No production code changed.

The archived Draft.urls and Editor.urls contracts promise full valid URL
strings for HTTP(S) and custom schemes. They do not specify every lexical
boundary. An exploratory opaque custom URI case such as obsidian:open was
not retained as a required assertion without native comparison. Do not infer
that all opaque schemes are supported, or add broad matching rules that could
treat ordinary colon-separated prose as a URL. Punctuation boundaries also
remain unverified. Both members remain partial.

The focused run passed 4 core methods across this suite and SyntaxActionAPITests,
plus 9 app methods in AutomationEditorContextTests. The new method expanded to
both runners. No window, permission prompt, or private URL was used. These
assertions do not establish native Drafts parity or all URL contracts.


### Draft update worker and rollback coverage — 20 October 2026

Refactored the two existing Draft.update contract tests to run on legacy and
worker execution. They check the void return, shared identity, immediate
editor-model updates, content, tags, flags, and exact storage-error result.
The storage-error case now performs an independent later commit and restores
a backup. It verifies that rejected text and revisions do not reappear.
No duplicate test methods or production changes were added.

The coordinator's focused run passed 48 methods across DraftMetadataContractTests,
WorkspaceDateBoundaryContractTests, and WorkspaceFilterContractTests. The two
update methods each passed both runner variants. These are in-memory checks;
native selection and Undo acceptance remain pending. No window opened.


### Workspace calendar-day boundary coverage — 20 October 2026

Added WorkspaceDateBoundaryContractTests for the shared filter evaluator.
The archived QueryDate contract ignores time components and includes the
whole selected calendar day. The test fixes the Gregorian calendar and
America/New_York time zone. It checks 8 March 2026 (23 hours) and 1 November 2026
(25 hours), created/modified/accessed fields, absolute dates, and relative
±1 day. For each start/end boundary it checks one millisecond outside, the
start, one millisecond before the next day, and the next day itself. Unknown
access dates stay unknown and are excluded from active access-date filters.

All six parameter combinations passed. No production defect was demonstrated.
The combined coordinator run passed 48 methods in three suites. This is direct
evaluator evidence; it does not establish JS property reconstruction, native
window results, or persistence after restart. Existing property tests remain
recorded separately, and startDate/endDate stay partial. No window opened.


### Native callback timeout acceptance — 20 October 2026

The production 120-second host/callback wait returned one final error before a
130-second neutral native reply. Late delivery did not run the sentinel,
change target text, or emit a second result. See validation.md for observation
times and build identity. Six app and three core focused callback tests passed.
Permission and capability lifetime checks remain pending; the contract is partial.


### Draft.update member acceptance — 20 October 2026

Native direct draft mutation/update preserved selected café, immediate text,
shared references, tags and flag. Command-Z/Redo restored the expected text
and selection; the second window showed the final state. Together with the
named normal/storage-error cases on both runners, this closes Draft.update
for the archived contract. The wider API and engine remain incomplete.


### Editor void return correction — 20 October 2026

undo, redo, showFind, showArrange, and showDictate now discard host values
and return undefined as documented. Both runners passed the specific return
assertions; full regression passed 450 app/482 core methods. Other acceptance
for these members remains separate. No native UI check was inferred.

The unsigned local Xcode build and matrix structure check passed. Installed
QA apps still use their previously recorded builds.


### Action catalog readonly correction — 20 October 2026

Action and ActionGroup now enforce the archived readonly identification
properties. Action configuration keeps its shared mutable contents while
rejecting property replacement. Both runners passed explicit reassignment
checks and full regression passed 453 app/484 core methods. Included-action
configuration precedence and other member acceptance remain pending.


### Syntax indentation completed — 20 October 2026

Local per-syntax Tab/2 Spaces/4 Spaces settings now drive native Tab, scripting
and built-in Indent/Outdent. Native QA verified four-space insertion, editing
buttons, Undo/Redo after a preference change, and two-space persistence after
restart. preferredTabString now has specific contract and native acceptance.
Full regression passed 453 app/484 core methods; final property tests passed 15.
This does not close all Editor Settings or remaining API contracts.


### Catalog identification members accepted — 20 October 2026

Native fixture and both-runner tests accepted Action.name/uuid/isSeparator
and ActionGroup.name, including readonly assignment rejection. Group rename
plus backup/restore preserved identity, but a legacy identifier collision
keeps ActionGroup.uuid partial. configuredValues,
recent usage, installation formats and broader group contracts remain partial.


### Action group identifier collision found — 20 October 2026

Before closing ActionGroup.uuid, compiled the current ActionGroupRecord
structure extracted verbatim from PresentationSettings.swift into a temporary
Foundation-only probe. Distinct valid names BAAAAAAAAAAAAAAAA (B plus 16 As)
and ?AAAAAAAAAAAAAAA (question mark plus 15 As) both produced
3F414141-4141-4141-4141-414141414141. The legacy sixteen-byte rolling algorithm
is not collision-safe. The probe did not open or change a library.

Readonly and rename/restore checks passed, but they do not prove uniqueness.
ActionGroup.uuid stays partial. Next: reproduce creation of both names through
the library in an isolated test, prevent replacement/data loss, and assign a
collision-safe identity while preserving existing stored and implicit IDs.
Do not replace every legacy group ID without a migration. No production
change for this issue has been made yet.


### Collision-safe group identity allocator — 20 October 2026

Added ActionGroupIdentity to reserve stored IDs, retain available preferred
IDs, and resolve legacy name collisions with deterministic SHA256-derived IDs.
The legacy constructor and identifier function remain unchanged. Six pure
tests passed for the known collision, input order, stored and preferred IDs,
and an occupied hash candidate. No test opened a window.

Library saves, scripting, and workspace consumers do not use this allocator
yet. The stored-group overwrite defect remains open. Next: add a failing
library regression, connect allocation to atomic saves and all consumers,
and verify restore and reopen. ActionGroup.uuid remains partial.


### Group save collision protection — 20 October 2026

Two isolated regression tests first failed with six issues: a new colliding
group replaced the stored group and retargeted its action; batch saves accepted
duplicate IDs. Single-group saves now allocate an unused identity for a new
legacy collision. Materialized implicit groups use the same reserved mapping.
Batch saves reject duplicate IDs before writes. Existing rename behavior stays
covered by the organization and both-runner catalog tests.

The final focused run passed 14 methods in four suites. The collision test also
checks backup restore and SQLite reopen. A separate case preserves an implicit
group and its action when a colliding explicit group is added. No automatic
test opens a window. Native verification of this change is pending.

ActionGroup.uuid remains partial. Remaining work: persist collision-safe IDs
when action saves create only implicit groups; unify scripting, workspace and
UI identity consumers; cover deletion, rollback, import and restore collisions.
Do not infer complete group identity acceptance from these save tests.


### Implicit group identity persistence — 20 October 2026

Collision groups created by action saves now receive stored IDs in the same
transaction. Existing implicit IDs take priority. Ordinary noncolliding groups
stay implicit. Deleted records are excluded from pending decoding. Scripting,
workspace resolution, settings and group management use the shared allocator.

The full regression passed 454 app methods and 496 core methods. A later
focused run also passed the legacy backup and group removal case. Unsigned
Xcode compilation passed. Structural matrix validation passed before the
evidence update. Tests cover both creation orders, stored identity, deletion,
restore, reopen, failed batch, both scripting runners and workspace UUID
lookup. No automatic test opens a window.

Native collision creation and import acceptance with the new binary remain
pending. ActionGroup.uuid stays partial. Next: verify neutral colliding groups
in QA, check imported identities against existing groups, and record the
native result. The earlier commit push failed DNS resolution; retry when
GitHub is reachable. No global or core parity closure is claimed.


### Native collision identity acceptance — 20 October 2026

Updated Visual QA from the successful unsigned build. Executable SHA256:
8393885e47da2ef0ef568a85da491c3c3f4f32d7ac1f67e7dc15d2df805d79dc.
Imported action-group-collision-actions.json through File > Import. The fixture
contains one action in B plus 16 As and another in question mark plus 15 As.
The verification action checked distinct UUIDs, separate membership and one
getAll entry per UUID. History showed Success. The neutral editor marker showed
C95E49A1-6E4A-8EB1-B316-F1199A92BB18 and
3F414141-4141-4141-4141-414141414141.

Quit and reopened the exact QA bundle. Selected the existing neutral note and
ran the same action again. It completed and returned the same two UUIDs.
QA retains one neutral note, update-qa and its flag. No permission changed.
No screenshot or raw log is tracked. The reproducible fixture is tracked.

Added single-file and multi-file import cases against an existing collision
owner. Both preserve its UUID and action membership, allocate a different UUID
for the imported group, keep IDs on repeated import, and roll back injected
write failures. The focused import regression passed 16 methods in two suites.
This closes ActionGroup.uuid only. Broader group methods, installation formats
and remaining included contracts still require their own acceptance.

Commits 41d038a and 13bfeba reached origin/main after DNS recovered. Continue
with the remaining ActionGroup contracts and the engine/native acceptance
items. The complete Mac roadmap remains open.


### ActionGroup query contracts — 21 October 2026

Read the frozen ActionGroup reference. Added three member-specific tests,
each on legacy and worker runners. find uses an exact Unicode name and
returns undefined for missing, case, prefix and whitespace variants. getAll
covers an empty catalog, empty and implicit groups, typed results, unique IDs
and local array mutation. actions covers empty groups, stored order, hidden
entries, separators, disabled steps, foreign-group exclusion and readonly
collection replacement. All three methods passed with six runner cases.

Earlier native catalog fixtures asserted installed and missing lookup,
getAll identity and separate membership. The specific new automatic cases
complete actions, find and getAll. This does not accept installation formats.

Found a concrete installation gap: groupInstallURL serializes only member
actions. Empty groups lose their name and group record in the link. The
installURL member stays partial. Next: add a group installation envelope,
preserve its record and options, keep older action links readable, and test
empty groups, populated groups and atomic import. Continue other engine and
Mac roadmap requirements after that work.


### Group installation envelope — 21 October 2026

The new contract test failed on both runners because the old link contained
only an action array. groupInstallURL now uses the existing backup envelope
with only its group record and ordered actions. This preserves empty groups,
name, ID, symbol and order. Sorted JSON keys keep repeated links stable.

installationData reads new envelopes and old JSON/base64 action links. It
limits an installation envelope to actions and groups; unrelated notes and
workspaces are not installed. The legacy installationActions adapter remains.
The URL router imports the data atomically. The review dialog shows group
names, permits an empty group, and saves through atomic library operations.
It no longer saves downloaded actions one at a time.

The full regression passed 455 app methods and 502 core methods. Unsigned
Xcode compilation passed. Specific tests cover both runners, empty/populated
Unicode group links, record and action preservation, stable readonly links,
rollback, base64 URL routing, repeated installation, unrelated-data exclusion
and legacy action decoding. No automatic test opens a window.

Native URL installation and the empty-group review dialog remain pending.
ActionGroup.installURL stays partial until those checks pass with the new
binary. Visual QA still uses the earlier collision-verification build. Next:
update that isolated bundle, import a neutral empty group, obtain its link,
and verify URL installation and the review dialog. The complete Mac roadmap
remains active.


### Native empty-group installation — 21 October 2026

Updated the isolated Visual QA bundle from the successful build. Executable
SHA256: 421225aab7bac23d331dada17f03f26047ec1cf8b1b46253f04105d7ef7c0c15.
The QA helper targeted the exact Visual QA bundle. Opened a neutral action URL
with the tracked action-group-installation-envelope.json payload. This created
QA Empty café 🐼 with ID BBBF0003-0000-4000-8000-000000000011, symbol
folder.fill and order 7. No actions were included in that group.

Imported action-group-installation-actions.json through File > Import. Ran
QA Empty group link against the existing neutral note. It checked the installed
group, empty membership, exported record, exact fields and stable link. The
editor displayed Empty group link passed café 🐼 and the generated URL.

Loaded that observed URL through Actions > Import from Directory. The review
displayed Group: QA Empty café 🐼 with an empty list and an enabled save
button. Saved it, ran the checker again, and verified two Success records in
History. Closed History. No permission changed. QA retains one neutral note,
its update-qa tag and flag. No screenshot or raw log is tracked.

This completes ActionGroup.installURL with the existing automatic populated
group, rollback and legacy-link cases. The fixture envelope is neutral input,
not a user backup. Replay it as URL data, import the checker, and run the action.
All ActionGroup members now have recorded acceptance; this does not close
Actions, the engine, other APIs, inspector, sync or the Mac roadmap. Next:
review Action.installURL and find with specific boundary cases, then resume
the remaining configuredValues/recent and engine acceptance work.


### Cloning resumed and Action.find accepted — 21 October 2026

The user resumed the eight cloning deliveries. The first functional correction
makes duplicate-name lookup stable across reload and backup restore. Both
execution routes passed specific tests. The signed isolated Engine QA checker
passed before and after restart, with two Success records. Action.find now has
member-specific complete evidence. Action.installURL is not accepted by that
checker alone. See validation for the executable and exact native scope.

Same-draft App Intent ownership with two windows passed on the signed QA image.
Both activation orders used the selected text from the intended window. See
validation for the specific native case. Next: remaining engine capability and
lifetime variants. Six engine records remain partial.
Line-up correction remains separate and pending. Do not close any full delivery
based on this one accepted member or the global number of passing tests.


### Action.installURL accepted — 21 October 2026

The member-specific getter test passed on both routes. Actual QA URL review,
save, replacement by identity, restart and execution passed. The neutral action
returned its expected UUID and History Success. No production change was needed.
See validation for exact fields and scope. Engine capability variants and the
remaining API contracts stay open; no full delivery is closed by this result.


### Apple model readiness rechecked — 21 October 2026

Current macOS 27.0.1 reports modelNotReady for on-device and systemNotReady for
PCC. Actual QA checked both explicit unavailable responses and History Success.
Both-mode negative tests passed. No setting or permission changed. Generation
and its native cancellation remain blocked by readiness; this is not a passed
cancellation check. Continue other engine and contract work independently.


### Action.recent boundary coverage — 21 October 2026

The specific saved-history case now covers both runners, date order, duplicate
use, rename, deletion, unknown identities, legacy records and nonmutating reads.
The method stays partial: recent use still depends on saved logs. Compare the
omitted-log behavior in Drafts before changing recency persistence. The accepted
find and installURL members do not close the remaining Action contracts.


### Typed other-action configuration correction — 21 October 2026

Catalog lookups now use the same Boolean/number conversion as execution. A
specific test failed first on both runners and passed after the correction.
The full suite passed 467 app and 512 core methods. Unsigned build and all
41 Python tooling tests passed. Strict engine/global gates remain open at
18/4,823 diagnostics. Persistent formats and current action/context sharing
stay unchanged. Updated native acceptance is
pending because the Mac locked before QA refresh. The member stays partial.


### Callback adapter absolute deadline — 21 October 2026

A controlled clock reproduced overdue success accepted before the timeout task
ran. The async callback adapter now starts its absolute deadline before opening
the destination and rejects overdue deliveries. Focused tests passed without
opening a URL or window. Full regression passed 468 app and512 core methods;
unsigned Xcode compilation passed. Native OS delivery of this boundary and the other engine acceptance items stay pending.


### Context.addSuccessParameter accepted — 21 October 2026

Both-runner member-specific boundaries and the existing actual callback delivery
record now complete this contract. The extension reuses the existing test and
adds no duplicate suite. Other Context members and the six partial engine
contracts remain open. No new native run is claimed while the Mac is locked.


### HTTP query values corrected — 21 October 2026

Added parameters now preserve literal plus signs. Existing raw and encoded query
values retain their original meaning. A real loopback server reproduced the
failure on both transport routes and confirmed the correction. The specific
builder regression also passed. HTTP timeout limits and remaining response
contracts required separate acceptance. The later HTTP object review records
that acceptance without closing the HTTPResponse object or the broader scope.


### HTTP timeout range corrected — 21 October 2026

Positive finite HTTP timeouts now retain their value, including values above
600 seconds. Invalid durations fail explicitly. The default remains 60 seconds;
engine deadlines stay unchanged. A specific regression failed first and passed
after correction. Broader HTTP evidence and classification follow separately.


### HTTP object contracts audited — 21 October 2026

Real loopback tests and both scripting routes cover the five HTTP object members.
Added independent worker cases for recoverable network failures, infrastructure
failure and typed cancellation. The query and timeout corrections have separate
commits. Full regression passed 468 app and 523 core methods; all 41 Python
tooling tests and the unsigned Xcode build passed. Structure validation has zero
errors. Strict engine/global gates remain open at 18/4,757 diagnostics.
HTTPResponse still needs its own review, including the unspecified otherData
condition. This does not close the broader integration or Mac scope.


### Native configuredValues acceptance — 21 October 2026

After unlock, refreshed and signed Engine QA. Actual typed source and lookup
actions both passed. The latter checked Boolean/number/Unicode-LF values through
find, group membership and recency while preserving its own context. The member
is complete with its existing specific automatic tests. Included configuration
precedence and other engine acceptance remain open. See validation for hashes.


### Updated-image native callback regression — 21 October 2026

The refreshed isolated QA passed success, error and cancellation callbacks.
After an actual delayed reply, the editor retained its later action result.
History confirmed the expected outcomes. Exact deadline-before-timer behavior
remains covered by controlled-clock tests, not this manual run. Native permission
and capability variants remain pending. See validation for timing limits.


### HTTPResponse charset and contracts — 21 October 2026

Declared response charsets now decode correctly. Three specific cases failed
before the correction. Actual loopback cases also check Latin-1, UTF-16 JSON,
HEAD and 204 metadata. The separate test cleanup fix bounds process teardown.
Full regression passed 468 app and 530 core methods; unsigned Xcode build passed.

The matrix accepts constructor, headers, statusCode and responseText. Four
members remain partial: non-JSON responseData, HTTP-status error policy,
unfollowed-redirect success policy and unspecified otherData population.
Do not infer their parity from successful HTTP requests. Current native QA
predates this charset change. Continue the unresolved reference comparisons
and other engine capability contracts before closing the wider delivery.


### XML-RPC decoded text corrected — 21 October 2026

A regression reproduced double decoding after HTTP charset conversion. XMLRPC
now keeps its UTF-8 conversion and the leading XML declaration consistent.
Actual Latin-1 and UTF-16 loopback requests passed on both scripting runners.
Malformed XML still fails explicitly. Full regression passed 468 app and 535
core methods; unsigned Xcode build passed. XML-RPC remains partial for its
other recorded contracts, including encoding detection without an HTTP charset.


### Context data access accepted — 21 October 2026

Specific both-engine tests and actual QA checks now accept previewValues and
appleScriptResponses. Native HTML checks cover keyed values; native AppleScript
checks cover mixed path order, record/list/null types and a caught error. A new
action verifies clean collections. The invalid initial AppleScript fixture and
successful repeat are recorded separately. No production Context code changed.

The matrix also gives configuredValues its own existing default/type/identity
and native evidence. Included-action collision precedence remains a partial
engine contract. callbackResponses and fail remain partial pending their specific
acceptance; these results do not close Context or the wider Mac scope.


### XML-RPC byte preservation — 21 October 2026

Original response bytes now reach XMLParser when HTTP has no charset. Both
engines passed real Latin-1, UTF-16 BOM and UTF-16 LE/BE declaration cases after
the corresponding regression failed first. Transport metadata remains private;
ordinary HTTP responses keep their shape. Guards preserve HTTP failures and
reject empty or malformed byte payloads. Full regression passed 468 app and
539 core methods. XML-RPC remains partial for its other specific contracts.


### Context.fail boundaries tested — 21 October 2026

The existing termination test now covers both engines, void return, omitted,
empty and Unicode messages, one exact log, and the fake notification payload.
The focused run passed 30 methods. The member remains partial: visible native
notification and presentation-policy behavior still need acceptance. The current
Action failed default is characterized without assigning it to the reference.


### XML-RPC structures and metadata — 21 October 2026

The parser now rejects malformed value shapes that previously lost content and
reported success. Empty and nested valid records/arrays, string whitespace and
existing extensions remain supported. Duplicate-name tolerance is unchanged.
See validation for the supplemental protocol reference and the failed regression.

Real loopback JavaScript checks on both engines accept XMLRPC.constructor and
XMLRPCResponse.constructor, error, faultCode, statusCode and success. Tests cover
success, negative/zero/positive faults, malformed payloads, HTTP failure and
disconnect. params and request remain partial for Date/binary mapping, complete
grammar, unknown charsets and other unresolved policies. Native engine acceptance
is separate. Full regression passed 468 app and 543 core methods; all 41 Python
tooling tests and the unsigned Xcode build passed.


### Context callback collection accepted — 21 October 2026

Both engines now have specific order/reset and unsuccessful-reply collection
assertions. Actual QA mixed callback and Shortcut steps/scripts, verified all
four responses, handled error/cancelled callbacks and checked a fresh execution.
The corrected neutral fixture passed; its initial URL-encoding failure remains
recorded. No production Context code changed. Only Context.fail remains partial
in this object. Engine permission/capability variants remain separate.

Full regression passed 468 app and 545 core methods. The unsigned Xcode build
and all 41 Python tooling tests passed. QA now has the validated HTTP/XML-RPC
runtime too; the manual acceptance here covers callbacks.


### Native transport response check — 21 October 2026

The installed Engine QA app passed the neutral HTTP/XML-RPC response fixture.
It checked Unicode, charsets, headers, fault codes and transport/parser failures
without changing editor text. See validation for the exact cases. Date/binary
mapping and undocumented response policies still require Drafts comparison.
No production change or new compatibility classification was made.


### XML-RPC parameter transport — 21 October 2026

Empty and nested parameter round trips now have specific real HTTP tests on
both engines and a successful installed-QA check. Values and response identity
remain intact. Date/binary and undefined input policies remain pending.


### Manual fixture identities — 21 October 2026

Corrected a transport fixture UUID that collided with the Window tab action.
A headless check now rejects duplicate explicit IDs across manual action-array
fixtures. Restored the QA catalog without deleting notes or action history.
This corrects test setup only. Production contracts remain unchanged.


### Action list preferences — 21 October 2026

Action-list options now expose Search, Action Log, group-bar visibility and
keyboard-shortcut labels. Visibility preferences are local. Shortcut formatting
shares normalization with validation; imported conflicts remain intact. Checked
626 core/524 app methods and unsigned compilation pass. Native interaction and
restart acceptance remain pending because CUA lost the QA menu. The reference
filter modes and full inspector/Settings delivery are still open.

## Dictation permission callback fix — 22 October 2026

The installed app crash report identifies an executor assertion in
`SystemDictationDriver.requestSpeechAuthorization`. The permission reply runs
on a background queue. The old closure inherited MainActor isolation before
it could dispatch its body to MainActor.

Permission replies now use an explicitly Sendable callback bridge. Speech
updates also use an explicitly Sendable entry closure. UI changes still run
on MainActor. A headless test sends granted and denied replies from a detached
task and checks MainActor delivery. All 23 dictation tests passed. No permission,
audio capture, or personal data was used by these tests.

The isolated local app build passed. Native permission acceptance and the
installed app update remain pending.
The usual app was not replaced. This is a functional fix, separate from the
completed Advanced Find refactoring.

## Editor syntax link templates — 22 October 2026

The editor did not turn custom syntax link templates into active links. The
shared definition now resolves templates by captured key. It uses the link
capture for the active UTF-16 range. Encoded values escape URL delimiters. Raw
values retain URL delimiters and existing escapes. Invalid URL characters are
escaped before Foundation constructs the URL, to prevent double encoding when
both placeholders occur in one template. Missing templates do not create links.
Disabled definitions remain inactive. Script link snapshots keep their format.

The editor applies resolved links only in link mode. The new windowless rendering
test checks the capture boundaries, mode changes, and retained text and selection.
The focused run passed four rendering methods and ten syntax methods. No native
click or Drafts comparison is claimed. The reference remains the archived syntax
format from 19 October. The current web guide was consulted only as a cross-check.

This change does not close Editor/scripting. Remaining acceptance includes tasks,
markers, built-in link templates and destinations, custom grammar features and
installation, advanced-find parity, full regression checks, and isolated native
verification. The usual installed app remains unchanged.

The isolated local Xcode build passed for this change.

## Syntax-based marker navigation — 22 October 2026

Previous Marker and Next Marker now use the assigned syntax definition, as
scripting does. They no longer parse Markdown headings with a separate regular
expression. They retain circular navigation and full marker selection. Selection
synchronizes with the native editor. Navigation does not change or save content.
A missing syntax reports an error instead of using Markdown markers.

Headless tests cover custom capture ranges with Unicode and CRLF, TaskPaper
projects, Plain Text, missing syntax, and native synchronization. Existing
Markdown navigation cases remain. Focused syntax, editing-bar and advanced-find
regressions passed. Native interaction and comparison with Drafts remain open.

## Syntax-based Toggle Tasks — 22 October 2026

The built-in editing command now advances task snapshots through the shared
syntax contract. It no longer uses a two-state Markdown regular expression.
Changes run from the last task to the first, so a replacement cannot invalidate
earlier UTF-16 positions. A nonempty selection limits changes to state ranges
inside that selection. An empty selection targets the whole draft. The final
selection accounts for changes in state length. Imported actions are unchanged.

Focused tests check custom states, different state lengths, Unicode, CRLF,
selection boundaries, TaskPaper dated completion, Plain Text, and stored text.
The existing Make Tasks and Toggle Tasks regression remains. Native interaction,
Undo acceptance and the remaining task presentation contracts are still open.

## Advanced Find reference observations — 22 October 2026

Computer Use opened Advanced Find in Drafts on the existing neutral draft
“Visual QA 49 — Tasks and lines”. After the draft loaded, the query “First”
produced one result, with line number and a Replace button. The dialog also
provides Reverse Values, Regular expressions, Ignore case, Find, Previous,
Next, Replace All and a history menu. The menu restores requests and offers
Clear History. No replacement or content edit was performed. The initial blank
editor produced no results; that state is not evidence of a search failure.
The previous native-find mode was restored and its panel was closed.

Draftly still needs per-result replacement, reversal, request history and further
behavior comparisons. The current sheet differs from the independent reference
window. These observations do not close advanced-find parity.

## Advanced Find individual replacement — 22 October 2026

Replace is now available for each result. The command resolves regex captures
against the full source, selects the inserted UTF-16 range, synchronizes the
editor, marks the change and saves. Invalid queries or unmatched ranges do not
mutate content. A save failure retains the text and pending state. Existing
Replace All and native-find behavior remain.

Full serial checks passed 666 app methods, 654 Core methods, 68 Python tests,
and the structural matrix check. Local build passed. Isolated Computer Use
verified replacement of only the second match, the result list, selection,
Undo/Redo and Markdown marker navigation. QA quit normally and was retired with
its closed data in recoverable Trash. Full remaining scope and exact limits:
`docs/editor-scripting-2026-10-22.md`. Editor/scripting remains incomplete.

## Advanced Find history and value reversal — 22 October 2026

Reverse Values swaps query and replacement without changing options or content.
Find and replacement commands save complete requests in device preferences.
History restores both texts and matching options. Exact duplicates move to the
front. Clear History removes only that key. The new glossary terms distinguish
a query from a complete request. Library and backup formats remain unchanged.

Three new headless methods cover persistence, labels, reversal, Unicode,
duplicates, isolation, invalid regex and corrupt history. Full serial runs passed
669 app methods/121 suites and 654 Core methods/124 suites. XML reports match the
discovered inventory. Python68, matrix structure0 and local build passed.

Isolated Computer Use verified reversal, restoration after option changes,
normal exit/relaunch persistence and Clear History with fields and source kept.
QA closed normally and was retired with recoverable data. Drafts54.1.1 confirmed
history restoration and labels. Its Reverse Values result was inconsistent in
automation and remains an explicit comparison limitation. The usual Draftly app
is unchanged. Remaining scope: docs/editor-scripting-2026-10-22.md.

## Independent Advanced Find window — 22 October 2026

Find is now a separate resizable window tied to its source editor. Explicit open
requests raise it and focus the query. Ordinary query and editor updates do not
raise it. Both fields accept multiple lines; Command-Return runs Find. Results
show line numbers. Escape and Done close Find, and source closure closes Find.
The model remains headless; LibraryView owns the native presentation bridge.

Native QA verified initial focus, multiline literal results and replacement,
source access with Find open, Undo without focus theft, returning to Find,
Escape and source closure. Focus and Escape defects found in the first QA build
were corrected and rechecked. QA was retired normally with recoverable data.
Full checks passed 671 app/654 Core methods, 68 Python, report inventory, local
build and matrix structure0. No test deadlines or retry rules changed.

The session also found a separate native-find routing defect when list focus
remains active. That correction is next. Full evidence and remaining scope:
docs/editor-scripting-2026-10-22.md. The usual app was not changed.

## Native Find source routing correction — 22 October 2026

The separate list-focus defect is corrected. The source focus hook runs before
the native Find command, and the command targets its source text view. A bound
renderer that rejects focus produces an error. A new headless regression failed
before the change and passed after it. Legacy headless calls remain compatible.

Isolated Computer Use verified Find from list focus, two native matches, source
selection, Advanced Find opening/Escape and return to native Find with text and
selection retained. QA closed normally and was retired with recoverable data.
Final app672/121 suites passed. Core654/124 passed before this app-only correction;
both reports match current discovery. Local build passed. showFind evidence was
updated with specific tests and native limits; its classification remains partial.
The usual app is unchanged. Full remaining scope is in the dated Editor record.


### Native syntax continuation — 22 October 2026

Shared task/link styles, syntax-defined Navigate, file bookmark save ordering and
grammar-defined Enter are implemented in separate commits. Isolated native QA
checked Markdown numbering/Undo/Redo, TaskPaper markers/continuation, and a neutral
file grammar with custom captures, three-state tasks, padded sequences and restart.
Drafts54.1.1 confirmed ordered task continuation, empty-item exit and spaced H1/H2
labels. Prefix spacing now has a specific correction and regression. Native check
of that correction remains pending. The neutral grammar is under scripts/fixtures.
QA quit and its exact registration was retired. Closed data is recoverable in
Trash. The usual app was not changed. Selection after Toggle Tasks needs a precise
before/after reproduction; the observation is not acceptance or a confirmed bug.

Full serial app677/121 and Core657/124 passed; reports match discovery. Python68,
matrix structure0 and the local Xcode build passed. See the dated Editor record
for remaining grammar, Find, file permission and reference checks. Full parity
remains open.


### Editor autocomplete — 22 October 2026

Syntax requests now feed a source-bound child panel. Keyboard selection preserves
result identity for equal labels. Markdown variants expose title/full-draft
triggers. Input refresh, stale source/selection/note guards, equivalent-definition
updates and Undo boundaries have specific tests. Native isolated QA checked the
visible list, duplicate-title selection, Escape and corrected Undo/Redo. Mouse
acceptance, deletion refresh, static/custom feature checks and Drafts comparison
remain pending. See the dated Editor continuation record for full scope.

The final serial app684/122 and Core661/124 passed; XML reports match discovery.
Python68, matrix structure0 and local Xcode build passed. Temporary trace code is
removed. QA was closed and retired to recoverable Trash with its exact registration
removed. The habitual app, its preferences and library were not changed.


### Completion refresh after deletion — 22 October 2026

Specific backward/forward deletion tests failed before the correction. The editor
now queues a guarded refresh after text-change notification. Explicit input,
cancellation, focus/context changes and acceptance invalidate older requests.
Nine focused methods passed. Isolated native QA checked backward deletion,
list reopening, title insertion, Undo/Redo and Escape. It quit normally and its
exact registration was retired. Its closed data remains recoverable in Trash.

The full serial app run passed687/122; XML matches discovery. Core sources are
unchanged and the prior661/124 report matches current inventory. Local build and
matrix structure0 passed. Forward native deletion, mouse/static suggestions,
feature toggles and the wider Editor/scripting objective remain pending.


### Autocomplete mouse acceptance — 22 October 2026

The actual content view failed its first-mouse policy check. Its hosting subclass
now accepts that click without making the panel key. Rows use a rectangular hit
area. Native QA confirmed a first-click draft insertion and a click in empty space
of an unselected static row. Duplicate labels inserted the correct second value.
A static template retained its current-title value, prefix and suffix. Typing and
Undo/Redo worked after draft acceptance. The neutral fixture includes these cases.

Ten focused methods, full app688/122, local build and matrix structure0 passed.
The app report matches discovery. Core is unchanged; prior661/124 still matches
inventory. QA quit and its exact registration was retired; data and runtimes are
recoverable in Trash. No habitual app, screenshot or raw-log change. Feature-toggle
persistence, IME/long lists/multiple windows, reference comparison and the broader
Editor/scripting scope remain open in the dated continuation record.

### Syntax feature acceptance — 22 October 2026

Autocomplete feature disable, restart persistence and re-enable passed in isolated
QA. Six theme rendering tests passed, including retained populated Undo/Redo.
Production is unchanged. Remaining syntax, link and Find scope stays open.
See docs/editor-scripting-2026-10-22.md.

### Built-in wiki destinations — 22 October 2026

Markdown wiki templates now connect to title/UUID opening, Quick Search and named
Workspace application. Imported templates and installation routes are retained.
Specific encoding, lookup, creation and failure tests passed. Full serial app692
and Core662 passed; local build and matrix structure passed. Native activation
and Drafts matching/default comparison remain pending. See the dated continuation.

### Title-link contract correction — 22 October 2026

Missing titles now require confirmation. Ambiguous titles warn and search instead
of choosing a note. Twelve focused URL methods, local build and matrix structure
passed. Native QA displayed encoded links, but both editor activation and Safari
delivery failed for the isolated scheme. Native routing remains pending. QA was
retired recoverably; usual app unchanged. The continuation records the separate
File Import syntax gap and the supplemental official reference.

### Syntax File Import — 22 October 2026

File Import now validates .draftsSyntax as a definition instead of a text draft.
Identical custom source retains identity; conflicts require reviewed replacement.
Red/green regression, thirty-two focused methods, Core665/124, local build and
matrix structure passed. Native QA confirmed installation in the syntax selector
with the note count unchanged. QA retired recoverably. See the dated continuation.

### Grammar hanging indentation — 22 October 2026

Shared UTF-16 prefix ranges now drive paragraph wrapping through indentationPatterns.
Markdown variants include the archived list/quote rule. Rendering retains source,
selection and paragraph settings. Focused Core21/app7, full app694/Core666, local
build and matrix structure passed. Native/tab/theme/reference checks remain pending.
See the dated continuation. This does not close Editor and scripting.

### Hanging indentation acceptance — 22 October 2026

Eight rendering tests passed, including four actual glyph-alignment cases for
spaces/tabs and normal/themed metrics. Native QA and Drafts54.1.1 showed the same
basic hanging alignment. QA Undo/Redo retained782 characters. Quote styling and
word-count differences are recorded separately. Native custom themes remain open.
QA retired recoverably; usual Draftly unchanged. See the dated continuation.

### Markdown quotation style — 22 October 2026

Shared built-in grammar now supplies quotation scopes. Default rendering italicizes
the body and attenuates markup. Red/green rendering regression, Core22/app9, local
build and matrix structure passed. Native rebuilt QA confirmed the correction on
the saved wrapping note. Broader styling and word-count parity remain open.
See the dated continuation. QA retired recoverably; usual app unchanged.

### Grammar validation — 22 October 2026

Known capture, scope, template and flag types now fail explicitly when malformed.
A red/green regression covers rejected installation; a positive case preserves
unknown fields and legacy defaults through import/backup. Core669/124, local build
and matrix structure passed. Incremental range evaluation and native replacement
acceptance remain open. See the dated continuation. Usual app unchanged.

### Exclusive syntax captures — 22 October 2026

Protected capture ranges no longer suppress later styles outside those ranges.
Captures apply in numeric order. Red/green Core cases and actual renderer fonts
passed; full app697/Core671, local build and matrix structure passed. Native custom
grammar reference comparison remains open. See the dated continuation.

### Syntax import choices — 22 October 2026

Reviewed syntax import supports replacement, named stored copies and cancellation.
Identity/name rules have four specific headless methods. Nine focused methods,
app701/123, local build and matrix structure passed. Native QA completed Cancel,
Copy and Replace; closed-library checks confirmed identities and unknown fields.
Built-in/file conflict and URL native checks remain pending. QA retired recoverably.
See the dated continuation. Usual app unchanged.

### Advanced Find source-window isolation — 22 October 2026

New two-editor Undo/replacement regression and eighteen Find methods passed.
Native QA confirmed independent replacements, retained second-panel state and
automatic panel closure with each source. Closed storage held both correct notes.
Reopen-query defaults still need Drafts comparison. No production source changed.
QA retired recoverably; usual app unchanged. See the dated continuation.

### Find reopening state — 22 October 2026

Drafts54.1.1 retained query, replacement and flags across close/reopen. A red/green
regression now covers interface reopening while preserving script initialization.
WindowModel retains the complete per-window request. Focused47, app703/123, local
build and matrix structure passed. Rebuilt native QA confirmed Done/native close
and unchanged source. QA retired recoverably. Restart/global defaults remain open.
See the dated continuation. Usual app unchanged.

### Advanced Find keyboard command — 22 October 2026

Native before/after control confirmed Command-Return failed in the multiline query
while the button worked. FindWindow now routes it to the shared Find command.
Headless key/command cases, focused21, app705/123, local build and matrix passed.
Native corrected QA confirmed history, ordinary Return, Escape and enabled
preferAdvancedFind routing. QAs retired recoverably; usual app unchanged.
Remaining keyboard/background/default/reference scope stays open.

### Injected file-syntax access — 22 October 2026

Library lookup now forwards injected preferences to bookmark reads, as it already
did for syntax features. A Core red/green regression verifies access and explicit
missing-bookmark failure without changing definitions. Combined integration
Core672/app707 and local build passed. Editor error presentation is separate.

### Visible syntax errors — 22 October 2026

The editor reports grammar-read failures and keeps text editable. File grammar
recovery uses the reviewed import path. Two headless cases and native missing-
bookmark/reselection/Undo/Redo passed. Full app707/Core672, local build and matrix
structure passed. Permission denial and other native errors remain open. QA
retired recoverably; usual app unchanged. See the dated continuation.

### Line task matching — 22 October 2026

Line-range definitions now expose one task per source line; task-range marks stay
independent. Core red/green and final legacy/worker cases passed with UTF-16/CRLF.
Core673 regression, local build and matrix structure passed. Native click/ignored-
mark/next-line/Undo checks passed with a tracked neutral grammar. QA retired
recoverably. Broader task and Drafts custom-grammar contracts remain open.

### Task labels by range type — 22 October 2026

Task mode ignores the line-only label capture; line mode retains it. A red/green
legacy/worker case checks labels, UTF-16 ranges and advancement. Older line
definitions without label still restore and derive their prior fallback. Focused32,
Core674/124, local build and matrix passed. No new native acceptance is claimed.

### Actions goal resumed — 22 October 2026

Actual Intent failure/recovery coverage passed for rejected promises and failure
after completion. Prior effects remain; tail and success effects stop. No runtime
change or native acceptance is claimed. See docs/actions-engine.md. The engine
goal remains open against docs/research/engine-native-checklist.md.

### Native Arrange close and recovery — 22 October 2026

File → Close All during an action Arrange dialog cancelled the run, removed the
panel, retained completed writes and stopped tail/Archive. A following action
succeeded. Closed storage matched the UI. QA retired recoverably; habitual app
unchanged. Individual-window closure and other native routes remain open. See
docs/validation.md, Native Arrange Close All.

### URL Prompt callbacks — 22 October 2026

Native URL Prompt Cancel, unchanged production timeout and following Accept each
delivered exactly one correct callback. Pending Prompt delivered none. Unicode
success parameters and closed history matched. Focused21 and fixture identity
check passed. Strict engine gate remains open (six partial contracts). QA/helper
retired recoverably; habitual app unchanged. See docs/validation.md.

### Callback cancellation race — 22 October 2026

Fixed acceptance of a callback after task cancellation but before MainActor
cleanup. A deterministic regression failed before the fix and passed after it.
Focused22, full app709 with matching inventory, local build and matrix structure
passed. No new native acceptance or app rollout. See docs/actions-engine.md.

### URL SelectPrompt timeout — 22 October 2026

Native URL SelectPrompt timed out at production settings, closed its panel, sent
one error callback and kept prior text in Inbox without success effects. A new
filtered selection returned selected=two once, saved success text and archived.
Closed storage matched. Core36 and fixture check passed. QA/helper retired
recoverably; usual app unchanged. Other native obligations remain open.

### Waited Shortcut process cleanup — 22 October 2026

Added two specific real-process adapter cases for cancellation and timeout while
waiting for Shortcut output. Both terminate the fixture process, remove input
and reject output. Process/Shortcut17 and local build passed. Native Shortcuts
service and entry-specific checks remain open; usual app unchanged.

### Native shell URL lifecycle — 22 October 2026

URL shell task cancel, production timeout and direct source close each returned
one correct callback and removed exact parent/child processes and temp folders.
Completed text stayed in Inbox without tail/Archive. Recovery worked both with
and without the original window. Closed history matched. Focused app15/Core2
passed. QA/helper retired recoverably; usual app unchanged. App Intent-specific
shell acceptance and other native routes remain open. See docs/validation.md.

### File selector cancellation race — 22 October 2026

Fixed a selector returning a late URL after task cancellation before queued
cleanup. Red/green regression also requires exactly one close. Existing write
and bookmark guards remain. Focused app17/Core6, full app711 with matching
inventory, local build and matrix passed. Native acceptance remains separate.

### Intent pending-save safety — 22 October 2026

Actual Intent.perform now has explicit target/other-draft save-failure and retry
cases. Pending text and storage diagnostics remain; no execution or reservation
starts. Focused14 and local build passed. No production change or native system
dispatch acceptance. Other Actions-engine obligations remain open.

### Integrated Actions regression — 22 October 2026

Core674/app712 passed with complete machine-readable inventory; Python68 passed.
No retries or deadlines changed. Strict engine acceptance still rejects six
partial records (18 diagnostics). Action.find duplicates follow the archived
first-match contract and already have native acceptance; they are not an open
defect. See docs/actions-engine.md and engine-native-checklist.md.

### Mail false-success correction — 22 October 2026

Native Mail composer handoff incorrectly returned sent before any send. Current
Mail.send now returns an explicit error through the legacy/async host before
opening that service. Confirmed delivery remains partial. Native corrected URL
error and recovery, app713/inventory and local build passed. No message sent.
See docs/validation.md. QA retired recoverably; habitual app unchanged.

### Mail failure through runners and Intent — 22 October 2026

Both runners, Mail step/scripting and actual Intent.perform now have explicit
no-false-success assertions. Prior effects persist, tail/Archive stop, ownership
releases and a following action succeeds. Focused19 and local build passed. No
production change; confirmed Mail delivery remains partial.

### Native file write-permission loss — 22 October 2026

Actual URL/bookmark save, filesystem write denial and recovery passed. The error
kept original file bytes and prior draft text in Inbox without tail/Archive.
Restored permissions reused the bookmark without another picker. File16/local
build passed. TCC/sandbox denial remains separate. QA retired recoverably.

### Export Close All lifetime — 22 October 2026

Native URL export cancelled through File Close All, removed its selector and
created no file. Completed text stayed in Inbox without tail/Archive. Following
export saved exact35-byte neutral content. Closed history matched. App25/Core6,
local build and matrix passed. QA retired recoverably; usual app unchanged.

### Notes sharing service lifetime — 22 October 2026

Native URL sharing through Notes passed Cancel and Save. Temporary file stayed
readable until service completion, then disappeared; Notes' copied attachment
opened with exact content afterward. One correct callback per run; tail/Archive
only on success. Test note moved recoverably to Recently Deleted. App17/Core6
and local build passed. QA retired; other sharing lifetimes remain open.

### Sharing timeout after handoff — 22 October 2026

Native Notes sharing timed out with one error while retaining its38-byte file.
A new action succeeded before the old dialog was cancelled. Late provider Cancel
removed the old file without another callback or changed result. Closed history
matched. App17/Core2 and local build passed. QA retired; usual app unchanged.
