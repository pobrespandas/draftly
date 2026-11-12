# Import, export, and recovery

Choose File → Export Full Backup to save a library backup. Keep the file outside the library folder and verify that you can find it before a broad change.

The library contains drafts, revisions, workspaces, actions, groups, and related configuration. File permissions stay on each Mac. A backup is not a grant to access the folders named by an imported action.

## Import files
File → Import accepts backups, Drafts JSON exports, text files, and action files. Review the selected source. A set of selected files imports as one operation: if validation fails, that operation must not leave a partial import.

Importing is not the same as restoring the complete library. Follow the displayed preview and confirmation for the operation you chose. Cancel if its scope is unclear.

## Agent imports and restores
An import commit must match its source and preview. If either changes, create a new preview. A full backup restore requires library scope and human review. Draftly makes a recovery copy and checks for pending editor changes before applying it.

## Recover text
For a recent editor change, try Undo in that editor. For saved content, inspect Versions. For a trashed draft, use Restore from Trash. For broader recovery, use a known backup. Do not empty Trash or overwrite a backup while diagnosing missing text.
