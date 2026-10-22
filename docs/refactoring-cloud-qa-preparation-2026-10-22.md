# Cloud QA preparation refactoring — 22 October 2026

## Reference and scope

This stage implements R5 from the modularity audit. The reference is 79327ee,
which contains R1 and R4. The worktree was clean and no build or test process
was active at the start. The isolated branch is
agent/cloud-qa-preparation-2026-10-22. The annotated reference tag is
pre-refactor-cloud-qa-preparation-2026-10-22. No previous work was removed.

The former script combined metadata rules, plist reads/writes and command-line
execution at module scope. Importing it also ran preparation. The refactoring
makes those responsibilities directly testable. Its command-line behavior and
identities stay unchanged. Safe import is the intended new internal boundary.

## Implemented boundaries

- cloud_qa_metadata receives template data, previous data and a generated ID.
  It returns prepared metadata and the decision to preserve previous metadata.
  It does not read files, write files, generate IDs or mutate the inputs.
- prepare owns reads, UUID generation and writes. It accepts explicit source
  and UUID dependencies for tests. Its defaults keep the existing behavior.
- main keeps the first destination argument and the current missing-argument
  error. Extra arguments remain ignored. The main guard prevents preparation
  during import.

The CLI still reads Configuration/Info.plist relative to the working directory.
It reads any previous destination before the template. It calls uuid.uuid4 once
per valid preparation, even when a matching container retains an existing ID.
It keeps existing empty or numeric IDs rather than adding validation. These are
characterized existing behaviors, not new policies.

The visible name remains Draftly iCloud QA. The QA container remains
iCloud.com.andrestobelem.draftly.cloudqa. The build wrapper still supplies
com.andrestobelem.draftly.cloud-qa. Main identity, team, main container, profiles,
entitlements, URL schemes and the Engine QA identity are unchanged. No identity
replacement or container creation was performed.

A matching QA container reuses the previous library ID, or uses the generated
ID if that key is absent. It does not replace Info.previous.plist. A non-empty
previous dictionary for another container is serialized to Info.previous.plist
before the destination is replaced. An empty dictionary does not replace the
backup. Existing backup files retain their current overwrite rules.

Template fields, including unknown fields and bundle placeholders, remain in
the output. The destination is refreshed from the template; old-only fields do
not merge into the new metadata. When a backup is required, it retains parsed
previous fields. A binary input backup still becomes the same default XML
serialization as before. No raw-copy or format migration rule was added.

Read and write errors still propagate. A completed backup remains if the later
target write fails. No rollback, directory creation, signing, installation or
new command-line option was added. App source, configuration and build wrapper
files did not change.

## Characterization and tests

Eight command-line characterization tests passed against the original script:
new destination; matching container and existing IDs; matching container without
an ID; changed container; empty previous dictionary; invalid source/destination
plists; failure at either write; and a real Python process with relative paths
and an ignored extra argument. The tests fix UUID generation and compare plist
content, backup bytes, error propagation and write order. They all passed again
after extraction.

Four boundary tests then passed: import with plist I/O and UUID generation
forbidden; pure transformation without input mutation or I/O; callable preparation
with an explicit template and UUID factory; and main argument handling. The
specific suite has 12 methods. Temporary directories, neutral metadata and
controlled UUIDs are used. Changes to process arguments and working directory
are scoped and restored. No original test or assertion was removed.

The real CLI test starts only Python against temporary plists. It does not run
the build wrapper, signing, LaunchServices or a native app. The existing build
wrapper tests separately keep their automatic/manual signing argument checks.
Their tools are mocked. No test requests a permission, opens a visible window,
plays audio or uses personal data.

## Baseline risk and final verification

Before script edits, all 68 Python tests passed. The complete Core baseline
reported one issue in AsyncHostDrainTests:
scriptRequestKeepsLibraryBusyUntilCancelledHostCleanupReturns(timeout: true)
ended before host.waitForStart succeeded. A separate serial run passed both
AsyncHostDrainTests methods. A separate app baseline passed all 777 methods.
The baseline local Debug build passed.

This failure preceded the refactoring. It is distinct from the earlier XML-RPC
baseline failure; no shared root cause was established. Keep it as an independent
concurrent test/startup risk. No timeout, retry rule, execution policy or engine
code was changed to hide it. The reference tag records this baseline limitation.

Final verification:

- The 12 preparation tests passed, including the eight original characterizations.
- All 80 Python tests passed.
- Complete Swift passed Core674/app777. XML reports matched the discovered
  inventory. Source files stayed frozen during the final run.
- Local Debug compilation passed after Swift tests finished.
- Structural API matrix and diff checks passed.
- Strict engine check retains six partial contracts and 18 diagnostics.

No new unresolved regression was observed. These results do not prove native
CloudKit access or synchronization. No signed cloud build or real cloud QA run
was performed. Raw outputs remain in /tmp/draftly-cloudqa-r5-* and are not tracked.

## Native verification and continuation

No Computer Use session was needed for this script-only extraction. No QA
installation, library, preference domain, profile or cloud data was changed.
The usual app stayed unchanged. Main was not advanced by this task. Publication
uses the isolated branch, based on R4.

R1, R4 and R5 are complete as refactoring stages. R2 styling is the next proposed
stage, followed by R3 text mutation. Functional cloning, native capability checks,
the host-start risk and the prior XML-RPC risk remain separate.
