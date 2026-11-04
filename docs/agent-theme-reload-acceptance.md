# Direct file-theme reload

`themes.reload` uses the native presentation revision. It does not replace the
stored theme definition or change either appearance reference. It requires an
explicit theme target, `appearance.manage`, `files.read`, resource access, and
the current definition token from `themes.get`.

The app reads the authorized file through its saved bookmark and bounded reader.
It checks the definition again at the preference commit boundary. A changed file
fails before the revision write. Only file themes support this operation.

The durable operation journal records submission before the preference write.
A recovered request returns its original result without another reload. A failure
after submission reports an unknown outcome and does not repeat the write.
The result contains the theme ID and effective definition token. It contains no
file path or theme content. File changes after the final check remain possible;
the operation does not lock files owned by another process.

Tests cover presentation cache invalidation, stale file rejection, exact reference
preservation, unchanged library definitions, denied resource or file access,
custom-theme rejection, invalid content, renamed content, and recovered requests.
Installed app acceptance remains pending. This report does not prove visible
refresh in a signed installed app or acceptance of every theme operation.

## Local validation

Strict validation passed 1 consumer, 193 contract, 824 Core and 1,670 app tests
(2,688 total). The native Debug build passed. Evidence is in
`/tmp/draftly-theme-reload-full` and `/tmp/draftly-theme-reload-build.log`.
Source coverage is 111 connected or conditional names of 137. The other 26 names
have no direct handler. CI acceptance of this source remains pending.
