# Action inspector completion — 22 October 2026

## Integration base

Main advanced from c82ae79 to616f71c by fast-forward. All ten published commits
remain intact. The annotated tag pre-inspector-integration-2026-10-22 retains the
old main. Both checkouts were clean. No build, test or QA process was active.
The entire diff was reviewed; production changes are limited to the audio tap
callback and transcription cancellation state. No identity or storage changed.

The exact branch tree passed complete Core679/app797 with XML/discovery match,
Python80, local Debug build and matrix structure0. The integrated Sources, Tests,
scripts, Configuration and project tree equals the validated branch tree.
No Swift build and test overlapped. Main and the tag are pushed. This is source
integration, not installation of the usual app or synchronization acceptance.

## Step inventory before edits

Every step retains Enabled. Fields below are execution inputs, not a claim of
full Drafts parity. Content uses template, then text, then [[draft]]. Aliases
must retain that precedence. Missing display defaults must not mutate imports.

| Step | Effective inputs and missing-value behavior | Inspector before this stage | Specific existing coverage |
| --- | --- | --- | --- |
| script | script/source; allowAsync/allowAsynchronous false; true/1 enable async | Stored fields only | ActionStepInspectorFieldsTests; worker tests |
| clipboard | content; writeType replace/append/prepend, default replace | Stored fields only | ActionEditingCopyTests; step executor tests |
| share | content | Stored fields only | Sharing lifetime tests |
| url | url falls back to content; encodeTags true unless false | Stored fields only | URL rendering tests |
| callbackUrl | URL inputs; waitForResponse true unless false | Stored fields only | Callback and async host tests |
| insertText | content | Stored fields only | Editor editing-flow tests |
| createDraft | content; folder/location inbox; flagged false; flagType; tags/assignTags; syntax aliases; openInEditor true | Open toggle; other stored fields | ActionCreateDraftEditingFlowTests |
| file | content; fileNameTemplate/name safe_title.md; useBookmark false; bookmarkName; folderTemplate; writeType create | Stored fields only | Action file conversion/bookmark tests |
| export | content; name safe_title.txt | Stored fields only | Export tests |
| openIn | content; name safe_title.txt | Stored fields only | Sharing file tests |
| runShortcut | name; content; waitForResponse true | Stored fields only | Shortcut launch tests |
| runAppleScript | script/source empty | Stored fields only | AppleScript transport tests |
| htmlpreview | content; hideInterface false | Stored fields only | HTML preview tests |
| defineTemplateTag | name/tagName; content | Stored fields only | Template tests |
| configureWindow | Seven tri-state switches and three named references | All supported controls already exposed | ActionWindowConfigurationEditingFlowTests |
| prompt | key/title/message/buttons/default text and two switches | All defaults and controls already exposed | ActionPromptEditingFlowTests |
| configurationKey | key/name/description/type/default/example/initial configuration | Dedicated typed controls | ActionConfigurationEditingFlowTests |
| includeAction | target uuid/name, distinct from step identity | Both targets already exposed | ActionIncludeEditingFlowTests |
| mail | content; recipients/subject; HTML/background switches | Stored fields only; actual send explicitly unavailable | Native message tests |
| message | content; recipients/subject; converter preserves other mail inputs | Stored fields only; actual send explicitly unavailable | Native message tests |
| listInReminders | content; list/listTemplate defaults Reminders | Stored fields only | Reminders host tests |
| reminder | content | Stored fields only | Event host tests |
| event | content | Stored fields only | Event host tests |
| print | content; format/printFormat Text or HTML; margins72 points | Stored fields only | Native print configuration tests |
| speak | content; autoStart/autoClose true unless false | Stored fields only | Speech request tests |

## Explicit limitations

The frozen system, utility and advanced step pages are the reference. There is
no archived services page for every file option. Do not invent missing contracts.
Reminder/Event separate list/title/notes, List in Reminders delimiter/first-line
list override, Shortcut Return to Drafts and file local/tagsTemplate/date options
are not connected by current execution. Preserve imported values and identify
these limits; do not add controls that imply an effect. Use Safari is iOS-specific.
The frozen reference does not define numeric platform mask meanings. The current
runtime does not filter by that mask. Preserve platform data without speculative
switches or a claim of platform support. This delivery records these blocks.

## Next batches

Expose absent execution fields and typed options through existing inspector
rules. Retain effective aliases and imported values. Expand symbol selection
without replacing unknown symbols. Keep editing temporary and preserve imported
shortcut conflicts when the shortcut itself is unchanged. Add specific tests.
Run separate neutral QA checks, then prepare the signed habitual update only
after data, preferences and signature checks. Pro comparison remains blocked.
The accepted microphone checks stay accepted and will not be repeated.


## Inspector controls and symbols

ActionSymbolCatalog retains the original twelve choices and expands to64 stable
entries. Search matches names, titles and keywords without changing order.
Manual names and unknown imported symbols stay exact. Search and opening the
picker do not write the selection. Four symbol tests cover these cases.

All25 types now expose their implemented execution inputs even when missing
from imported data. Boolean controls retain the existing distinct true/1 and
non-false policies. Modes use choices; print margins use a numeric adjustment
and retain invalid imported text for correction. Imported unknown choice values
remain selectable. Effective aliases stay editable without inserting shadowing
canonical keys. Inactive imported aliases have distinct labels and raw editors.
Template tag insertion appends to the visible fallback value.

Prompt, Configure Window, Configured Value and Include Action retain their
existing specialized controls and tests. Execution limitations are visible for
message delivery, reminder/event separate inputs, List in Reminders, Shortcut
Return to Drafts and imported unsupported file/platform data. No platform mask
semantics or new runtime capability was invented.

The combined focused38 methods passed in nine suites. New cases cover all25
input sets without writes, alias precedence, Boolean coercion, unknown choices,
print defaults against the actual native consumer, tag insertion, and legacy/
worker execution of edited file/clipboard options. The execution case also
checks raw fields, identity, temporary edits and backup round-trip. Local Debug
build passed. No automatic test opened a visible window or external service.
The first compile placed a numeric UI helper in the wrong view scope; moving it
to the owning inspector fixed the compile. No runtime/test deadline changed.
Native binding checks and complete final regression follow separately.


## Imported shortcut conflicts

The existing Save guard rejected an unchanged conflicting imported shortcut,
preventing edits to unrelated options. A new regression failed with the New
Draft conflict. ActionEditingCopy now distinguishes preservation of an existing
stored action's original shortcut from assigning a new shortcut. The conflict
warning remains visible. Save permits the unchanged imported shortcut but still
rejects a conflicting new/duplicated action or changed shortcut. The global
shortcut validator and imported data are unchanged. Focused app24/Core9 and
local Debug build passed. No external shortcut or visible window was used.
