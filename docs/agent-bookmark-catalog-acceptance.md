# Scoped bookmark catalog

`bookmarks.list` returns only permitted aliases, resource IDs and opaque version
tokens. It does not return paths or saved permission bytes. It resolves no file
URL. Paging uses the common connection/grant snapshot rules.

The native bookmark store now keeps local generations. The resource ID binds
the alias, generation and permission bytes. Identical saved bytes keep the ID.
Changed permissions, forgetting/recreation and corrupt metadata create new IDs.
A metadata entry cannot directly choose an old ID for changed permission bytes.
Failed metadata persistence returns no new identity. Existing native Settings
and Action writes use the same store.

The native grant picker and resolver use the same preference domain as the
service. Tests supply isolated domains. A changed or forgotten permission no
longer resolves under its old identity. Themes also appear in resource choices.

Local validation passed the complete strict Swift inventory: 1 consumer,
183 contract, 822 Core and 1,608 app tests (2,614 total). The native Debug build
and two project checks passed. A focused test also checked invalidation after
all transports for that connection had closed.

Installed acceptance remains open. `bookmarks.requestAdd` and `bookmarks.forget`
still need their reviewed agent handlers. Bookmark and HTTPS backup sources
still return `interaction_required` pending their effect routes. Catalog support
does not prove file access, restoration or signed update acceptance.
