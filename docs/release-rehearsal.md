# Release rehearsal

The Release rehearsal workflow checks a candidate source tree. It does not
create a release, sign a distribution app, or deploy the website. It has no
access to signing secrets or write permissions.

Start it manually with an existing tag in the form `vMAJOR.MINOR.PATCH`. The
tag must identify the current `main` commit. It must match
`CFBundleShortVersionString`. `CFBundleVersion` must be a positive integer.
The workflow runs the test suites, matrix structural check, and local build.
It checks the built app identity and URL scheme. The local build uses an ad hoc
signature. It is not a release package.

## Before enabling publication

- Keep `DRAFTLY_UPDATES_ENABLED` unset until update termination and active
  Actions have been verified. Do not use a test key for a public build.
- Verify the updater, signed feed, and key recovery process.
- Add and verify Developer ID signing, notarization, and the production
  CloudKit profile. Verify all nested code and the installed app.
- Check that the candidate build number is greater than every published build.
  Reject duplicate releases and concurrent publication.
- Publish the package and verify its public bytes before changing the feed.
  Preserve the current site and feed if a later step fails.
- Test a release with two distinct signed executables and a copied library.
  Verify cancellation, recovery, offline behavior, and update authenticity.
- Validate CloudKit Production migration separately. The rehearsal does not
  test synchronization or move Development records.

Do not use the rehearsal as evidence that a public release is ready. A tag
push does not start a publication in this version of the workflow.
