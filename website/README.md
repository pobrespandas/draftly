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

The availability section reads `/appcast.xml` from the same site. It shows
the download, minimum macOS version, and GitHub release notes when the feed
has a valid version and the expected GitHub asset URL. If the feed is missing,
invalid, redirected, or unavailable, the site keeps the development message.
The page checks metadata, not the Sparkle signature. Release staging and
publication must verify the signed feed and public assets before promotion.

Run the availability tests with `node --test website/release.test.mjs` from
the repository root. This source change is not a deployment. The live site
must receive the page and script together through a coordinated deployment
that preserves the appcast and other site files.
