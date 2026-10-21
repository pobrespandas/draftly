# Vendor sources

`provenance.json` records the upstream archives and their original hashes.
Local patches do not change those archive hashes.

## MultiMarkdown random footnote destinations

Draftly patches `CMultiMarkdown/src/html.c` in
`mmd_export_footnote_list_html`. Random footnote destinations use the same
existing ID calculation as their references and backlinks. The upstream code
prints sequential destination IDs even when references use random IDs. This
breaks navigation. Displayed footnote numbers remain sequential.

The patch applies only when `EXT_RANDOM_FOOT` is enabled. The regression in
`MultiMarkdownRandomFootnoteTests` checks matching destinations, content and
backlinks for one and three footnotes. It also checks the exact random-off HTML
bytes captured before the patch. Preserve this patch when updating the vendor
sources. This is a local correctness fix, not proof of complete Drafts parity.
