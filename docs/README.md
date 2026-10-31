# Draftly documentation

Choose the guide for what you want to do. You do not need the development or
signing guides to install the released app.

## Use the app

- [Get started](getting-started.md): install Draftly, capture text, find drafts,
  use Actions, personalize the editor, and back up your library.
- [Action compatibility](compatibility.md): which scripting behavior is covered
  and which integrations still need checks.
- [Current progress](project-progress.md): what shipped and what remains open.

## Work on the code

- [Development](development.md): requirements, local builds, signing, data
  formats, and the repository map.
- [Testing](testing.md): run checks, use isolated fixtures, and preserve coverage.
- [Architecture](architecture.md): module responsibilities and refactoring records.
- [Glossary](../GLOSSARY.md): terms used in the code and guides.
- [Product direction](../PRODUCT.md) and [constitution](../CONSTITUTION.md):
  the purpose and principles behind product decisions.

## Maintain and publish Draftly

- [Release operations](releasing.md): prepare, verify, publish, and recover a release.
- [CI/CD](ci-cd.md): which checks run and how publication is controlled.
- [iCloud and signing](icloud-distribution.md): maintainer configuration for
  development and personal builds.
- [Manual engine QA](manual-engine-qa.md) and [VM checklist](utm-icloud-validation.md):
  native checks that automated tests do not replace.
- [Repository maintenance](repository-maintenance.md): cleanup decisions and
  files that must remain local.

## Read historical evidence

- [Mission, vision, and values](research/mission-vision-values-2026-10-31.md):
  origins, differences between frameworks, evidence, and use in Draftly.

Use [project progress](project-progress.md) for the current work list.
Dated audits and [validation records](validation.md) describe the versions
checked at the time. Old pending statements are not new instructions.
Frozen references are in `research`; previous status summaries are in `archive`.
The [Actions matrix](research/action-api-matrix.json) is a technical contract
inventory, not a percentage of compatibility.

Raw QA captures, logs, credentials, personal libraries, and operation journals
stay outside Git. The ignored `claude-handoff.md` holds local continuation
notes when present. The real app image used by the website is an intentional
tracked product asset.
