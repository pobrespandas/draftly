# Agent Instructions

## Continuation

- To resume Draftly work, read `docs/claude-handoff.md` first when it exists.
  It contains local operation journals and unfinished checks. Then read
  `docs/project-progress.md` for the tracked state and next work.
- Use `docs/README.md` to find maintained guides. Dated audits and archived
  checkpoints record their original scope; they are not the current task list.

## Product decisions

- For product, design, or architecture decisions, read `PRODUCT.md`,
  `MISSION.md`, `VISION.md`, `VALUES.md`, and `CONSTITUTION.md`. They provide
  revisable direction, values, and decision principles.

## Commits

- Use Conventional Commits with a required scope: `type(scope): description`.
  Example: `feat(editor): add autosave`.
- Make atomic commits. Each commit must contain one logical change and its
  related tests and documentation. Put independent changes in separate commits.
- Never add `Co-authored-by` trailers to commit messages.

## Technical Writing

- Follow ASD-STE100 (Simplified Technical English) in English documentation
  and code comments.
- Use short sentences, active voice, and clear instructions.
- Use the same term for the same concept. Keep technical names and identifiers
  unchanged.
