# Draftly website

The website is a static Firebase Hosting site in the `gen-lang-client-0607406471`
project. Its Hosting site ID is `draftly-pobrespandas-prod`.

Preview it from this directory:

```sh
python3 -m http.server 8000 --directory public
```

To publish, sign in to Firebase CLI with an account that can deploy to the
project, then run:

```sh
firebase deploy --only hosting
```

The custom domain is `draftly.pobrespandas.com`. Its DNS and certificate
must be configured in Firebase Hosting and Cloudflare.
