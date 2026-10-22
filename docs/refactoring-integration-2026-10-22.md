# Refactoring integration — 22 October 2026

## Scope and history

This integration brings the five bounded modularity refactorings into main.
The previous main and origin/main both pointed to 5494342. The accumulated
refactoring branch pointed to ebf7e39. Both worktrees were clean. No build or
test process was active at the start.

5494342 is an ancestor of ebf7e39. The integration uses fast-forward history.
It keeps the existing design-system commit 80b8ecb and all earlier work. It does
not squash, rebase or rewrite the five refactoring commits:

| Stage | Commit | Boundary |
| --- | --- | --- |
| R1 | b39c643 | Editor completion context, independent of Touch Bar |
| R4 | 79327ee | Workspace preparation, with caller effects kept in order |
| R5 | 62b280e | Cloud QA metadata, file operations and CLI entry |
| R2 | 15d1610 | Editor syntax styling, independent of text coordination |
| R3 | ebf7e39 | Shared text mutation, with distinct update-route policies |

The individual stage records retain their characterization, baseline failures
and limits. Their statements about main describe the state at each stage.
This integration record and current status describe the integrated state.
Existing branches and reference tags remain available.

## Verification

The integration candidate contains the exact production and test tree at
ebf7e39. No production code or test changed during integration. The only new
commit records the integration and updates current documentation.

The complete Swift runner passed Core674 and app785. It matched XML test
identities to the discovered inventory. Python80 passed. The local Debug app
build passed after Swift tests ended. Source and tests stayed fixed during
validation. No build and Swift test run overlapped.

The structural matrix passed with zero errors. The strict engine gate still
has six partial contracts and 18 diagnostics. Its output matches the R3 result
exactly. These compatibility limits are not integration regressions and are
not accepted as complete. Diff checks passed.

The earlier host-start and XML-RPC timing failures did not appear in this run.
They remain known risks. No retry, timeout or scheduling change was added.
Outputs use /tmp/draftly-refactor-integration-* and are not versioned.

Tests used neutral data and hidden hosts. They did not show, activate or move
windows, request permissions, play sounds or use personal data. No new manual
Computer Use session was required for a history integration with no code change.

## Limits and continuation

The usual app was not opened, installed or replaced. There was no signing,
profile, identity, permission or CloudKit change. A local build is not evidence
of synchronization. No native, visual or complete compatibility acceptance is
added by this integration.

Continue from main. Functional work on the inspector, Workspaces, Settings and
personalization remains in the handoff and status. Further refactoring needs a
new bounded diagnosis. This integration completes R1–R5, not Draftly cloning.
