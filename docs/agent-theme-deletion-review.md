# Theme deletion contract review

The direct `themes.delete` handler is not available yet. It must require the
app-owned destructive review and bind that review to the target version. A CLI
or model response cannot approve the request.

The library now has `commitThemeDeletion`. It deletes the theme record and saves
the mutation receipt in the same transaction. A failed final authority check
rolls back both changes. A reopened store returns the receipt without another
delete. The focused test also checks that another theme and a draft remain.

## Remaining integration

- Validate the target, resource scope, expected version and retry identity.
- Resolve review effects again before approval consumption and commit.
- Recover the durable deletion receipt before checking target existence.
- Remove the saved file bookmark through the app-owned preferences. Do not read
  or delete the source file. Bind cleanup to the deleted theme identity.
- Keep configured references and workspace rules consistent with native deletion.
- Record uncertain post-submission outcomes without automatic replay.
- Test revocation, Stop Work, cancellation, stale review, preference write failure,
  restart recovery and installed native review.

This storage change does not increase the number of connected operations. It
does not prove that bookmark cleanup and library deletion form one transaction.

Focused validation passed all 24 mutation-receipt tests. The log is
`/tmp/draftly-theme-deletion-storage.log`. Full-source CI remains pending.
