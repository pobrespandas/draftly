# Bind bookmark identities to saved permissions

Derive each agent bookmark ID from the alias, saved permission bytes and a local
generation. This prevents a changed permission from keeping an old grant's
resource ID, even if its cached fingerprint is edited. Forgetting and recreating
a bookmark starts a new generation.

Keep this metadata with the existing device-local bookmark preferences. Persist
new generations before returning IDs. Any change in permission bytes creates a
new identity; an OS bookmark refresh can therefore require a new scoped grant.
Catalog reads resolve no file URL. File access still needs the current grant and
its own effect checks. Native permission storage and library backups stay
separate.
