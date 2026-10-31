# CI and publication

## Check selection

CI selects checks on Ubuntu before it allocates a Mac runner. The selector is
`scripts/ci-change-scope.py`. Its tests cover deleted and renamed files,
unknown inputs, missing revisions, mixed changes, and final job results.

| Changed input | Checks |
| --- | --- |
| Documentation and repository guidance | Selection and final result |
| Website code | Website tests on Ubuntu |
| Scripts and release workflows | Script tests on macOS |
| Actions contract data | Matrix structure on Ubuntu |
| App, resources, dependencies, native tests, or build drivers | Native tests, local build, script tests, matrix structure |
| Unknown input | All checks |

Script tests stay on macOS because some test macOS command adapters. They do
not compile the app. Native compilation and Swift tests have their own job.
Explicit diagnostics select their native check. A manual full run selects all
checks. A missing revision selects all checks; an unreadable revision fails.

The required check retains the name `Build and test on macOS` for compatibility
with branch protection. It now reports the combined result on Ubuntu. Each
selected job must succeed. Each unselected job must be skipped. A failed,
cancelled, missing, or unexpectedly skipped job fails the required check.
This follows GitHub's documented [job dependency rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-jobs).

## Validation

Run the script suite, website tests, matrix structural check, and `actionlint`
when changing workflow selection. The actionlint configuration declares the
existing `xcode-27` runner label. Run native tests and a local build when the
selector or native workflow changes. Keep generated reports outside Git.

A successful local run is not a protected PR check. GitHub must recognize the
required check on the PR before integration. Source, signed candidate, public
release, website promotion, and installed app are separate states.
