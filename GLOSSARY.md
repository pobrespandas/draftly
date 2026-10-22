# Draftly

Draftly is a Mac app for text capture and actions.

## Language

### Drafts and organization

**Draft**:
A text item with its own identity, content, tags, and organization state.
_Avoid_: Note

**Temporary draft**:
A draft that has not yet been saved in the library. It can be the current draft without appearing in the draft list.

**Saved draft**:
A draft stored in the library. An empty draft can be saved if it has tags or a flag.

**Current draft**:
The draft open in a window's editor. It can remain open when the draft list has multiple selected drafts.
_Avoid_: Selected draft (when referring to the editor)

**Selected drafts**:
The drafts selected in a window's draft list for an operation. The selection can contain more than one draft.
_Avoid_: Current drafts

**Draft list**:
The ordered list of saved drafts that match the current draft view and filters.

**Draft preview**:
A text excerpt from a draft's content below its title in the draft list.
_Avoid_: Markdown preview

**Markdown preview**:
The rendered presentation of a draft's Markdown content.
_Avoid_: Draft preview

**Duplicate draft**:
An independent copy of a draft in Inbox, with a new identity and dates. It retains the source content, tags, flag, and syntax, but not its history.

**Merged draft**:
A new Inbox draft that combines the content and tags of selected drafts. The source drafts retain their identities and content. Their organization state can change during the merge.

**Draft export**:
A file containing selected drafts as text, CSV, or JSON. It is separate from a full backup.

**Library**:
The collection of saved drafts, revisions, workspaces, actions, action groups, syntax definitions, themes, and execution history.

**Tag**:
A label attached to a draft for classification and filtering. A draft can have more than one tag.

**Organization state**:
A draft's archive and trash status. A flag is a separate marker.

**Workspace**:
A draft view definition with filters, a sort order, and presentation options. It can be saved or applied directly.
_Avoid_: Folder, container

**Applied workspace**:
The workspace definition currently used by a window. It can differ from its saved definition and from local list settings.

**Local list settings**:
The draft list display and search options chosen on this Mac for use without an applied workspace.

**Draft view**:
A named selection of drafts based on their organization state or flag. Inbox, Archive, Trash, All, and Flagged are draft views.
_Avoid_: Folder

**Inbox**:
The draft view that contains drafts outside Archive and Trash.

**Archive**:
The draft view that contains archived drafts outside Trash.

**Trash**:
The draft view that contains drafts marked as trashed. These drafts retain their content, tags, flag, and archive status.

**All**:
The draft view that contains every draft outside Trash, including archived drafts.

**Flag**:
A marker on a draft that remains when the draft is in Trash.

**Flagged**:
The draft view that contains flagged drafts outside Trash, including archived drafts.

**Revision**:
A saved snapshot of a draft's content at a specific time. It does not include the draft's tags or organization state.
_Avoid_: Full draft snapshot

**Pinned draft**:
The current draft kept open when the user returns to the app after the new-draft timeout.

**Capture**:
Incoming text held separately from an editor draft until it is saved or discarded. It can become a new draft or be added to an existing draft.

### Editor appearance

**Theme**:
A named definition of colors for the editor and its interface.

**Custom theme**:
A theme definition saved in the library for use without its original external file.

**File theme**:
A theme definition maintained in an external file. It is distinct from an imported custom theme.

**Theme development folder**:
A folder of external theme definitions used while creating and editing themes.

**Configured theme**:
The theme chosen on this Mac for light or dark appearance. A workspace can specify a different theme for its window.

### Editor search

**Find query**:
The text or regular expression used to locate matches in the current draft.

**Find request**:
A find query, replacement text, and matching options that can be used together again.
_Avoid_: Query (when referring to the complete request)

**Find history**:
The recent find requests available for reuse on this device.

### Syntax

**Syntax feature**:
An optional behavior declared by a syntax, with a default value that the user can
override on the current device. A rule can require one or more enabled features.

**Hanging indentation**:
The offset of wrapped lines after the first line of a paragraph. A syntax can
set this offset from a captured prefix without adding spaces to the source.

**Task label**:
The text associated with a task, separate from its state and interactive mark.

**Task state**:
The value that records the progress of a task.

**Interactive task mark**:
The text that a user clicks or taps to change a task state.

### Actions

**Step creation default**:
An option value added when a new action step is created. It does not fill missing options in an imported step.

**Step fallback**:
An option value used when the action author has not supplied one. An explicit empty value can have a different meaning.

**Action configuration**:
Values that a user chooses for the configured-value steps of an action.

**Configuration default**:
A value supplied by an action author before the user chooses a value.

**Confirmed configuration**:
Action configuration that the user has accepted. A default alone is not confirmation.

**Action**:
A named sequence of steps that performs work with a draft.
_Avoid_: Script (for the whole action)

**Action editing copy**:
A temporary copy of an action. Its changes become part of the saved action only when the user saves them.

**Action step**:
One operation in an action's ordered sequence. A step can be enabled or disabled.

**Action group**:
A named collection of actions. Each action belongs to one action group.

**Action catalog**:
The actions and action groups available in a library, including their organization and visibility.

**Included action**:
An action whose enabled steps form part of another action's sequence.

**Queued action**:
An action scheduled to run on a specified draft after the current action succeeds.

**Script**:
Instructions used by a script step in an action.

**After-success behavior**:
The choice to keep, archive, or trash the source draft when an action succeeds.
_Avoid_: Success disposition, follow-up action

**Action run**:
An attempt to execute an action on a draft, with an outcome and messages. Failure or cancellation can leave changes from completed steps in place.

**Action execution session**:
The live execution of an action and its queued actions, with one identity, a current step, and one final outcome.
_Avoid_: Execution history (for a live execution)

**Action execution report**:
The final outcome of an action execution session, including its termination reason and successful callback values. It is separate from a saved execution-history record.

**Execution history**:
The saved records of action runs.
_Avoid_: Action history

**Action cancellation**:
An outcome that stops the remaining steps and queued actions without applying the cancelled action's after-success behavior. Changes already made can remain.

**Sharing handoff**:
The transfer of a draft item to a system sharing service. The service can still need the item after the action has ended.

**Template**:
Text that contains placeholders for draft content, dates, or other values.

**Template tag**:
A named placeholder replaced with a value when a template is rendered. It is separate from a tag attached to a draft.

### Backup and import

**Full backup**:
A saved copy of drafts, revisions, workspaces, actions, action groups, syntax definitions, themes, and execution history. Credentials and local file permissions are separate from the backup.

**Backup import**:
A merge of a full backup into the library. When a draft with the same identity has different content or metadata, both copies are kept.
_Avoid_: Library replacement

### Action resources

**Credential**:
A named set of authentication values available to action scripts on this Mac.

**Library folder**:
The local folder for files read or written by action scripts. It is separate from the library of drafts and actions.

**Named export folder**:
A folder chosen by the user and recalled by name for file exports on this Mac.
