# Release operations

This guide is for maintainers who publish the Mac app. Public downloads are
hosted on GitHub Releases. The website and signed update catalog, called the
appcast, tell users which version is available. Preparing files does not make
them public; publication and the website update are separate steps.

Use [CI/CD](ci-cd.md) for workflow selection and publication gates. Use
[project progress](project-progress.md) for the current pending release.
The [rehearsal record](release-rehearsal.md) preserves implementation history
and dated acceptance. Its old pending statements are not current instructions.

## Release channels

Use `vMAJOR.MINOR.PATCH` for a stable release. Use `vMAJOR.MINOR.PATCH-alpha.N`
or `vMAJOR.MINOR.PATCH-beta.N` for a prerelease. Start N at 1. The numeric part
must match `CFBundleShortVersionString`. Keep `CFBundleVersion` increasing
across all three channels, including the later stable release.

All channels require the same rehearsal, Developer ID signature, notarization,
and candidate verification. A candidate or workflow artifact is not a download
offer. Alpha and beta files stay in a private GitHub draft until all expected
assets have uploaded and their hashes match. Publication marks them as a
prerelease and never makes them the latest stable release. The publisher then
checks the public downloads. An uncertain result requires inspection before
recovery; it does not permit replacing public assets.

Alpha and beta publication does not deploy Firebase or change the stable
appcast. The website's main download stays on the verified stable feed.
Prerelease users currently receive stable-channel update checks. There is no
automatic alpha or beta update feed in this change. Agent access stays off by
default in every channel.

## Prepare source

1. Validate the PR and integrate it through branch protection.
2. Confirm the release commit, version, and build before creating its tag.
3. For an automated release, use a commit without a CI skip instruction.
   GitHub applies those instructions to push events, including the tag
   dispatcher. See [GitHub's skip rules](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs).
   Create the version tag once, on the integrated commit. Keep published tags
   and assets immutable. Do not create a tag while a candidate PR is pending.
4. Run the release preflight. It requires HEAD, main, and tag to match. Package
   inputs must differ from the latest stable release. A version-only change
   does not qualify.

A normal main push or PR does not publish. A version tag requests the trusted
main workflow. Explicit recovery resumes its original candidate; it does not
rebuild different bytes under an existing public version.

## Build and verify

The package command creates the Developer ID app and ZIP. With `--dmg`, it
also creates, signs, notarizes, and staples the DMG from that same app. Preserve
the candidate metadata, checksums, disk-image manifest, and READY marker.

Verify effective bundle identity, team, entitlements, profile, signature,
notarization, and Gatekeeper. The existing iCloud container stays unchanged.
Signing does not prove synchronization. Test the exact candidate required by
the change. A fresh-install fix needs an empty local library and preference
domains before launch, with no repair helper or manually written marker.

Use an isolated directory for candidates. Keep credentials in the protected
release environment or local credential store. Never pass secrets in command
arguments or print them. Keep packages and logs outside Git.

## Publish a stable release in order

1. Prepare and verify the signed appcast. Preserve existing release items.
2. Acquire the site writer lock. Inspect the current live site and stage a
   new version that preserves its files and configuration.
3. Stage the GitHub draft. Verify source identity and all expected assets,
   including the DMG manifest when present.
4. Publish and download the public assets. Verify sizes and hashes.
5. Promote the exact staged Firebase version. Verify the public signed feed
   and both website download buttons. Each must use the new version's DMG.
6. Release only the lock owned by this operation after verification succeeds.

The scripts keep durable journals outside Git. A lost response is an unknown
outcome, not permission to repeat a publication or promotion. Inspect remote
state and use the matching recovery path. Never clear an unfamiliar lock.
The website is in project `gen-lang-client-0607406471`, site
`draftly-pobrespandas-prod`, at `draftly.pobrespandas.com`.

## Recovery and acceptance

Keep the previous package before replacing an installed app. Keep a coherent
library copy when testing migrations. Check library, preferences, Services,
URLs, restart, and update behavior for the affected installation.

For a defective public release, withdraw its update offer through a coordinated
feed deployment and publish a correction with a higher version and build.
Preserve old assets. Do not replace bytes or move tags of a published version.
Keep distribution, updates, and CloudKit acceptance separate.
