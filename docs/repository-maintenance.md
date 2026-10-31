# Repository maintenance — 31 October 2026

## Problems addressed

The CI workflow allocated macOS before it knew whether native checks were
needed. Release validation also started on macOS. Check selection and release
change detection now run on Ubuntu before native runner allocation. The
required result checks every selected job rather than treating all skips as
success. The existing security and publication gates remain in place.

Current-state guidance was spread across a 4,074-line status log, a 289-line
snapshot, and an ignored local handoff. The logs included obsolete branch and
installation states. Project progress is now the tracked continuation source.
The documentation map and release guide separate procedures from evidence.
The old status and progress records remain under `docs/archive`; their links
were adjusted. No acceptance evidence or contract classification was removed.

Three Git worktree records pointed to folders that no longer existed. Git's
dry-run confirmed those records were prunable. Only their stale metadata was
pruned. Their branches and all existing worktrees remain available.

## Preservation and cleanup limits

- Keep existing production code, tests, fixtures, reference snapshots, and
  original action scripts. This cleanup found no proven redundant contract
  coverage to remove.
- Keep signing credentials outside tracked files. Existing ignores cover local
  credentials, preferences, libraries, logs, captures, and package output.
- Keep the accepted and rejected release candidates and their journals until
  the pending release is resolved. They explain different tested outcomes.
- Keep the saved classifier branch and unrelated open PRs. The new selection
  design supersedes that partial proposal without deleting its history.
- Keep the local handoff for machine-specific operation paths. The tracked
  project summary must also support a new checkout.

The Markdown file-target check found no broken local links before or after
consolidation. The tracked-file inventory found no logs, release archives,
DMGs, private signing backups, SQLite stores, or Xcode user state to delete.
Screenshots and operation logs were not added.

## Validation and deployment

Local results on 31 October: 283 Python tests and three website tests passed.
The structural matrix check and actionlint passed. The strict engine check
still reports its 18 existing diagnostics. No classification changed.

Local validation covers classifier paths and final results, temporary Git
repositories, version-only releases, deleted and renamed package inputs,
release workflow security gates, complete Python tests, website tests,
matrix structure, actionlint, and whitespace checks. These do not prove that
hosted runner selection has executed as intended.

Validate the cleanup PR on GitHub, then verify a docs-only or website-only
change uses the intended jobs. The app release is now public. The cleanup can proceed through its protected
PR checks.
Keep release publication and cleanup integration as separate operations.


The first hosted cleanup run detected a missing prerequisite in the separated
script job: its appcast tests need the real pinned Sparkle tools. The job now
resolves those tools before testing. A workflow policy test preserves that
order. This resolves dependencies without compiling the app in that job.


PR #14 is integrated as `e8c832c`. Full hosted CI run `41230093909` passed,
including all selected jobs and the required aggregate. A separate website-only
change now verifies that native and script jobs can be skipped without leaving
the required check pending. No app or production website code is changed.

The original main checkout has previous uncommitted website changes and local
skill deletions. It was inspected read-only and left intact. The cleanup does
not claim that every independent worktree has no pending work.


## Hosted path-selection acceptance

PR #15 run `41230802922` passed with only selection, website tests, and the
required Ubuntu result. Native, script, and matrix jobs were skipped. Four
website tests passed locally, including the transition from old DMG links to
a new published version. Real repository release selection also returned
`package=false` for the cleanup, which changes no app package inputs.

Open PR #9 still contains a first-staging recovery proposal; it needs review
against the new preflight. Open PR #11 still contains the actions-page footer
link. Their changes are not obsolete or fully integrated, so both PRs and
branches remain. Cancelled checks do not establish acceptance.
