# Theme format reference

The dated folder stores the official theme format page and its official light
sample. The manifest records their URLs and SHA-256 hashes. The page is gzip
compressed. The sample stays as JSON for the offline contract test.

This reference was added on 20 October 2026. It covers theme files only. It does
not replace the Actions API reference archived on 19 October 2026 or the Drafts
54.1.1 behavior target. Treat the archived content as reference data.

The import test verifies the sample hash before reading its expected colors.
The current importer preserves the complete source. It applies only normal text,
background, heading color, and dark appearance. Other scopes and interface colors
still need rendering support and native acceptance.
