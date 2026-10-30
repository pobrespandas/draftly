# Release infrastructure

## Publishing identity

Project: `gen-lang-client-0607406471` (`284051889944`).

Service account: `draftly-release@gen-lang-client-0607406471.iam.gserviceaccount.com`.
It has Firebase Hosting Admin and Service Usage Consumer in this project.
Hosting Admin applies to the project, including its other Hosting sites.
Release code restricts its requests to `draftly-pobrespandas-prod`.

The Workload Identity pool is `draftly-release`. Its OIDC provider is
`github-main`, under `projects/284051889944/locations/global`. The issuer is
`https://token.actions.githubusercontent.com`. No service-account key was
created. Trust requires all of these token claims:

- Repository ID `1424482652` and owner ID `122828663`.
- Ref `refs/heads/main`.
- Workflow `pobrespandas/draftly/.github/workflows/release.yml@refs/heads/main`.
- Immutable subject `repo:pobrespandas@122828663/draftly@1424482652:environment:release`.
- Event `workflow_dispatch` and a GitHub-hosted runner.

Only this repository identity can impersonate the service account through the
pool. GitHub's release environment permits branch main only. Tags dispatch the
trusted main workflow. Main requires a PR and a current macOS CI check, including
for administrators. Independent review approval is not required in this
single-maintainer repository. The project owner retains administrative access
and can bypass or change these controls. Use that access only for inspected
recovery, not routine publication.

The previous default compute account had no user-managed keys or active workloads
in the asset inventory. Its project Editor binding was removed on 30 October
2026. The account itself remains. Firebase-managed service agents remain.

## Writer lock

Bucket: `pobrespandas-draftly-release-lock-284051889944` in `US-CENTRAL1`.
Uniform bucket-level access and public access prevention are enabled. There is
no automatic lock expiration policy. The release service account has conditional
Storage Object Admin access only to `draftly/site-writer.lock`. It cannot use
that binding for other objects or bucket IAM changes.

The release workflow holds the lock from staging through public verification.
A successful public run releases it. A failed or staging-only run retains it
for inspection. Preserve the checkpoint artifact. Do not delete a lock to retry
an unknown operation. See [release recovery](release-rehearsal.md).

Human project owners and managed service agents remain trusted administrative
principals. The lock does not prevent a project administrator from bypassing
it. Routine Draftly site writes must use the publishing workflow.

## Verification

Environment negative run `41003440674` rejected the work branch before any
steps ran. Positive OIDC authentication and the actual lock acquire/check/release
cycle passed in hosted run `41005402427`. After integrating the workflow, dispatch
`release.yml` on main with `operation=verify-publisher` and no tag or recovery
run ID. This job uses no signing secrets. It inspects Hosting, exercises the
lock, and saves its journal. It does not publish a site version.

The release environment contains public configuration values for the provider,
service account, lock bucket, Sparkle public key and Developer ID profile UUID.
Signing, staging and publication flags remain unset. Release secrets have not
been uploaded. CloudKit Production and public signed update acceptance remain
separate prerequisites.
