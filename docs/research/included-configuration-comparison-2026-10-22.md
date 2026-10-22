# Included configuration comparison — 22 October 2026

## Reference attempt

Manual Computer Use confirmed Drafts 54.1.1 (943) in About. The Actions menu had
no groups. Manage Action Groups allowed creation and naming of the empty group
QA Included Configuration 20261022. Its action list was empty. Pressing the
Add Action button opened Drafts Pro, which lists action creation/customization
as a paid feature. The Pro dialog was closed without purchase, trial, restore,
account change or scripting execution. The group manager and About were closed.

The empty neutral group remains for a later reference session. No action was
created or run. No personal draft or filter was edited. No subscription or preference control
was changed.
The empty group is not an authentic exported action-group fixture.

CFG-01 through CFG-05 are REFERENCE-blocked by this observed Pro restriction.
SEP-01/02 also still require an authentic exported container. No precedence
result is accepted from Drafts. Do not change rules from these characterizations.

## Repeatable observation fixture

Tests/DraftlyCoreTests/Fixtures/included-configuration-observer.js defines
qaIncludedObserve(stage) and qaIncludedFinish(). It records stage, JavaScript
type and value of context.configuredValues.label. An absent key records type
undefined and JSON null. The finish operation writes the observations to the
neutral current draft. There is no network, clipboard, message or external effect.
The automatic tests use this exact script as a packaged resource.

In a future Pro session, create a neutral draft and actions in the QA group.
Do not run the probe on a personal draft. Put the observer script first in the
root, followed by draft.setTemplateTag('qaSuffix',''). Set initial configuration
requirements off for these precedence cases. They do not replace the already
accepted first-use prompt/cancel tests.

For each case, create children and root with the following fields and scripts.
Use a fresh root for each variant. Repeat inclusion by selected UUID, literal
name and a template name formed as ChildName[[qaSuffix]]. Do not assert a Drafts
winner in the observation script. Save the full JSON observation as text evidence,
with version, entry, field values and observed action identity.

| Case | Setup and scripts | Current Draftly observations; not Drafts acceptance |
| --- | --- | --- |
| CFG-01 | Child string label default Child default; saved child label Child saved. Root has no label. Child: qaIncludedObserve('child'). Root tail: qaIncludedFinish(). | All three resolution routes and both runners yield string Child default. Child saved value stays stored unchanged. |
| CFG-02 | Root string label default Root default; child default Child default. Child observes; root finishes. Repeat with root saved label Root saved. | Without root saved value: static yields Child default; template yields Root default. With root saved value: both yield Root saved. |
| CFG-03 | Root label string Root text. Child label number 7, then separate Boolean true. Child observes; root finishes. Use defaultNumberValue and defaultBoolValue in Draftly fixtures. | Static yields number 7 or Boolean true. Template preserves string Root text. |
| CFG-04 | Root has no label. Child default Child default. Observe before include, in child and after include; finish. | Static already exposes Child default before inclusion. Template has undefined/null before inclusion, then Child default inside and after. |
| CFG-05 | First child default First; second default Second. Include First twice, then Second twice. Each observes its name and appends ! to context.configuredValues.label; root finishes. | Static starts Second and retains each runtime edit. Template starts First and retains each runtime edit. Each run has one root log. |

Use the reference app's supported configuration UI for saved values. Record
that setup separately. Do not inject Draftly metadata into Drafts or treat a
changed default as a saved child value. If that UI path is unavailable, keep the
saved-value variant blocked. Repeat each reference case after normal restart
when saved values are involved.
Record both action.configuredValues and context.configuredValues if the reference
exposes a distinct result. The current fixture characterizes context only; it
must not be used to infer every saved-value or required-field policy.

## Automatic characterization

IncludedConfigurationCharacterizationTests has five methods and 30 runner
executions across its parameter cases and field variants. It checks values,
types, timing, repeated siblings and unchanged stored actions. Both legacy and
async runners execute the cases. Name/UUID/template resolution is explicit in
CFG-01; the collision, type, timing and sibling cases use UUID and template.
All use neutral in-memory data. They do not open windows or request permissions.

The baseline focused run passed 43 methods. After adding the five methods, the
focused run passed 48. A first fixture run used defaultBooleanValue instead of
the existing defaultBoolValue key and observed false. Correcting the fixture key
made the intended Boolean-true case pass. This was a test-input correction;
no implementation rule was changed.

These are characterization tests. If Drafts later establishes another rule,
record the mismatch, add the reference-backed regression and change the rule in
a separate functional commit. Do not report current behavior as parity.

## Implementation boundaries and current evidence

ActionStepExpansion expands static includes before bootstrap. Configuration
values are then evaluated against the root action. Additional dynamic values
are inserted only for absent keys by ActionExecutionConfiguration. This explains
the observations; it does not prove that Drafts uses the same rules.

Production, public APIs, identities, library formats and existing scripts remain
unchanged. The five original action fixtures remain unchanged. The API matrix
retains six partial engine contracts and the strict gate retains 18 diagnostics.
Native evidence records only the observed block, not a passed comparison.

Complete final verification passed Core 679 and app 785 with XML results matched
to the discovered inventory. Python 80 passed. The focused run passed 48 methods.
The local Debug build passed. Structural matrix 0 and diff checks passed; the
strict engine gate still reports 18 diagnostics. No timeout, retry or scheduling
rule changed. Source/tests stayed fixed during the full run. Swift tests and
build did not overlap. Outputs use /tmp/draftly-included-config-* and are not
versioned. No QA app was installed or usual Draftly app changed.
