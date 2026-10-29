# Draftly website

The website is a static Firebase Hosting site in the `pobrespandas-home`
project. Its Hosting site ID is `draftly-pobrespandas`.

Preview it from this directory:

```sh
python3 -m http.server 8000 --directory public
```

Do not deploy this directory directly. A Firebase Hosting deployment replaces
the live file set. It could remove the update feed or files from another site
writer. The release staging process preserves the current live files and
configuration, but it does not promote a version. See
[`docs/release-rehearsal.md`](../docs/release-rehearsal.md) for its checks and
the remaining publication requirements. Coordinate all site writers before
enabling publication.

The custom domain is `draftly.pobrespandas.com`. Its DNS and certificate
must be configured in Firebase Hosting and Cloudflare.
