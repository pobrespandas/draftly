# Development with agents

Use this guide when a task needs a product, design, or architecture decision.
For build commands and repository navigation, use [Development](development.md).

## Direction, rules, and evidence

These documents help agents make decisions within the user's task. Each source
has a distinct role. Read the sources that apply to the decision at hand.

| Source | Role | Consult it when |
| --- | --- | --- |
| [Mission](../MISSION.md) | Purpose and people served. | Assessing whether a change helps the writing process. |
| [Vision](../VISION.md) | Long-term direction. | Comparing future product directions. |
| [Values](../VALUES.md) | Criteria for trade-offs. | A choice helps one concern but harms another. |
| [Constitution](../CONSTITUTION.md) | Principles for product and engineering decisions. | Designing, implementing, or reviewing a change. |
| [Product](../PRODUCT.md) | Audience, scope, and current priorities. | Choosing or proposing product work. |
| [Agent instructions](../AGENTS.md) | Repository workflow and skill entry points. | Starting work or choosing a method. |
| [Current progress](project-progress.md) | Recorded implementation and validation status. | Establishing the baseline or reporting completion. |
| Code and relevant tests | Actual rules and tested behavior. | Checking a claim or changing behavior. |
| [Research](research/mission-vision-values-2026-10-31.md) | Sources, arguments, and limits. | Reconsidering the framework or its assumptions. |

Direction guides choices. The user's request defines the authorized task.
A mission or vision does not authorize extra features. When a trade-off requires
a scope change, explain the alternatives and obtain the user's decision before
doing the additional work.

The constitution describes intended practice. Current progress and validation
records describe what has been implemented and checked. Confirm claims against
the relevant code, tests, and observed behavior. Record a conflict explicitly
rather than treating an intended principle as proof of current behavior.

Research recommendations remain proposals until the project adopts them.
Keep external findings separate from project decisions.

## Apply principles to a change

State the concrete problem and the proposed behavior. Use the relevant principle
to explain a real choice. Keep routine changes brief; explain material trade-offs.

For a capture task, simplicity can support fewer steps. Trust can support keeping
the captured text when saving fails. Validate both results: the normal capture
flow and the failure path. A statement that the change follows the values is
not evidence that either result works.

For a refactoring task, use the design-principles skill linked from AGENTS.md.
Identify the responsibility or dependency that causes a concrete problem.
Verify that the change preserves the required behavior.

## Record results

Keep each rule in its existing source. Link to that source instead of copying
its text into more files. Record a change to direction or principles in the
document that owns it.

In the task report and current progress, separate implementation, automated
tests, real-use checks, user confirmation, and blocked checks. State which
evidence supports completion. Preserve the limits of that evidence.

This guide establishes the initial use of the documents. A broader review of
their wording and usefulness remains future work.
