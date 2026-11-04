# Local theme installation and replacement

`themes.install` and `themes.replace` connect when the host has preference storage
and the durable operation registry. They require appearance management and file
read capabilities. Call them directly, then wait for the accepted operation.
They do not use `mutations.prepare`.

## Inputs and preconditions

Supported inputs are inline native or Drafts JSON, a ready connection-owned
transfer, a scoped saved directory bookmark, and a built-in or custom installation
link. Theme bytes use the same limit as the file-theme reader. HTTPS input still
returns `interactionRequired`. Its reviewed network route remains unimplemented.
These connected names are not complete acceptance of every source variant.

File mode requires bookmark input. The resolver reads through pinned directory
handles, captures a narrower file permission while the file descriptor is live,
and checks the permission's resolved device, inode, size and modification metadata
against that descriptor. Permission bytes stay inside the app. The effect owner
checks the original bookmark identity and current file definition again before
saving. Custom mode uses its captured definition without another source read.

New installation does not silently replace an existing ID or same-type name.
Use explicit replacement with the stored target token from `themes.list`.
Replacement requires target access. It can repair a missing original file without
reading that file. The old source file is not changed or deleted. It keeps the target ID and type, and rejects
conflicts with another installed theme. It cannot replace a record with a built-in
name. Optional selection needs the separate appearance token from
`themes.selection` as `expectedSelectionVersion`.

## Commit and recovery

The operation captures its resolved input before launch. Live authority and current
preconditions are checked at the library commit boundary. The journal records
submission before the theme and library receipt commit together. Saved permission,
selection references and the local presentation revision then use one compared
preference-domain write. Unknown preference fields and the other appearance stay.
The result exposes only resource identifiers, version tokens and built-in names.
Creating a resource does not broaden the connection's grant.

Library records and preferences are separate stores. A failure after submission
reports an unknown outcome. It does not automatically undo or repeat partial
changes. A retry or recreated service checks the durable operation first and
returns its original result without resolving the source, installing or selecting
again. An uncertain operation remains uncertain. Do not present it as success.

## Validation and remaining gates

The complete run verified 1 consumer, 193 contract, 826 Core and 1,681 app
tests (2,701 total). Native Debug passed. Evidence:
`/tmp/draftly-theme-install-verified.log`,
`/tmp/draftly-theme-install-verified` and
`/tmp/draftly-theme-install-verified-build.log`.

The run includes the four focused suites, twelve installation source and
optional-selection cases, replacement of a missing original file, recreated-service
recovery without source access, preference failure, authority loss, failed library
storage, changed files including NFC/NFD, revoked bookmarks and stale selection.
Local input tests cover 24 cases with and without file-permission capture.

Signed installed behavior, process interruption between stores, production file
permissions and reviewed HTTPS resolution remain open. File-theme tokens now bind the saved file permission. Local tests reject stale
work after a same-content retarget. Installed retarget acceptance remains open. Local file I/O remains synchronous, as in the existing theme
reader; mounted-file latency also needs acceptance. The agent distribution and
client gates remain open. Do not treat source coverage as release acceptance.

## Permission-bound file tokens

File-theme versions combine the definition with a hash of the saved permission.
The whole value uses the reader's private HMAC key. Neither the permission bytes
nor their hash appears as a result field. Custom-theme versions keep their
existing form. Listing uses the stored definition and permission; file reads use
the current file definition and permission.

Installation computes its result token against the new permission before saving
and checks the preference write before success. Tests compare that token with a
subsequent `themes.get`. A retarget between preparation and execution invalidates
the stored target token, even when both files have identical definitions.

The permission-bound source passed 19 focused tests in three suites. Five cases
cover stale replacement before and after acceptance, reload, selection and a
pending destructive review. All keep the retargeted permission and stored theme.
Strict validation passed 1 consumer, 193 contract, 826 Core and 1,682 app tests
(2,702 total). Native Debug passed. Logs:
`/tmp/draftly-theme-permission-version-expanded.log`,
`/tmp/draftly-theme-permission-version-full.log` and
`/tmp/draftly-theme-permission-version-build.log`. Installed acceptance remains
open. These results supersede the earlier source's local totals above.

## Reviewed HTTPS inputs

The parent command now owns the reviewed HTTPS download. The local input reader
still rejects network input. See [HTTPS input evidence](agent-https-input-acceptance.md)
for authority checks, limits, recovery and acceptance gaps.
