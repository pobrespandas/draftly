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

## Semantic versions and changelog

Use [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). Draftly's
public contracts include its documented scripting API, CLI and MCP contracts,
URL actions, export formats, and data migration guarantees. Record incompatible
changes explicitly. From 1.0.0, use major for incompatible changes, minor for
compatible features, and patch for fixes. During 0.x, use minor for features
or incompatible changes and patch for fixes. This 0.x rule is Draftly policy;
SemVer does not promise a stable API before 1.0.0.

Use scoped [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
Mark incompatible changes with `!` or a `BREAKING CHANGE:` footer. The note
generator uses those markers to recommend a minimum version. It retains legacy
subjects in Other changes so they remain visible for review. It does not infer
all compatibility changes from source code. A maintainer must review the notes
and version before creating a tag.

Preview the notes from the previous stable tag:

```sh
python3 scripts/prepare-release-notes.py --since v0.1.9 --tag v0.2.0-alpha.1
```

After review, use `--write` to add `docs/releases/v0.2.0-alpha.1.txt` and the same
entry in `CHANGELOG.md`. The command does not change the app version, build,
Git tags, GitHub, or the live website. It refuses to overwrite existing release
notes or changelog entries. A release preflight requires one changelog entry
that exactly matches the reviewed release notes.

Use the previous stable tag as the baseline for alpha, beta, and final notes.
This gives each release a complete change list. Alpha and beta are below the
stable version with the same numeric part. Sequence numbers compare as numbers:
alpha.2 is before alpha.10; alpha is before beta; beta is before stable. Keep
published tags and assets immutable. Do not rewrite old version numbers to
apply the new policy retroactively.

The initial changelog includes only the eight releases that GitHub reported
as public during this change. It excludes unpublished 0.1.4 and 0.1.8 candidates.
A changelog entry alone does not prove that a download is public or ready.
