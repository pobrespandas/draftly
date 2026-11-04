# Theme deletion contract review

The direct `themes.delete` handler requires the app-owned destructive review.
The review binds the stored definition version from `themes.list`. A CLI or model
response cannot approve the request. File themes do not require a source-file
read. The source file can be missing or inaccessible.

The library now has `commitThemeDeletion`. It deletes the theme record and saves
the mutation receipt in the same transaction. A failed final authority check
rolls back both changes. A reopened store returns the receipt without another
delete. The focused test also checks that another theme and a draft remain.

## Host behavior

The handler validates retry identity and target version before it opens review.
It resolves review effects again and checks authority at the commit boundary.
The shared journal records submission. The library commits the deleted record
and its receipt together. Saved-bookmark cleanup follows that commit. These two
stores do not form one transaction. A post-submission failure is uncertain.

Recovery checks the durable receipt before target existence. It can finish orphan
bookmark cleanup while the target is absent. It skips cleanup if another theme
now has the same ID. A succeeded request cannot delete that replacement.
Configured references remain, as with native deletion. The presentation resolver
uses its existing fallback when the installed theme no longer exists.

The review states that drafts and source files remain. The handler does not read
or delete a source file. It removes only the target ID's saved file permission.

## Acceptance still required

Signed installed review, interruption between stores, denied operating-system
preference writes and visible fallback remain open. This handler is not a release
acceptance claim. The full agent publication gates remain open.

Focused validation passed all 24 mutation-receipt tests. The log is
`/tmp/draftly-theme-deletion-storage.log`. Full-source CI remains pending.

## Connected-handler evidence

Seven review scenarios passed: approve, deny, cancel, authority invalidation,
changed definition, failed storage and transport closure. Recovery after service
restart preserves a replacement theme with the same ID. A file-theme test uses
no `files.read`, preserves source bytes, removes its saved bookmark, and keeps
an unrelated bookmark. Availability requires review and operation control.

Strict validation passed 1 consumer, 193 contract, 825 Core and 1,673 app tests
(2,692 total). The native Debug build passed after project regeneration added the
new source file. Logs: `/tmp/draftly-theme-delete-full.log` and
`/tmp/draftly-theme-delete-build.log`. Current-source CI remains pending.
