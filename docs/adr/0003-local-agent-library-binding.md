# Bind agent access to one local store instance

Use a private, versioned agent library ID beside the local SQLite store. Match it
against the real storage location, Core Data store UUID, volume UUID and file ID.
Keep Note and Core Data metadata unchanged. A copied, moved or replaced store
requires a new binding instead of inheriting old connection grants.

Core Data's store UUID alone is insufficient: copying a store can duplicate it.
The binding also remains device-local; CloudKit records and library backups do
not contain it. A separate local identity avoids changing the public library
format or treating synchronized replicas as one permission boundary.

Acquire both a location lock and a physical-file lock before reading or creating
the binding. The location lock also excludes replacement or identity-file deletion
while a host is alive. The physical lock covers aliases of the same file. Lock
files remain in place after release. Validate the loaded store, held descriptors,
current paths and binding bytes before admitting work. A changed or untrusted
owner ends that host epoch; restoring an old file does not revive it. Temporary
lock contention denies that attempt without changing authority.

The identity filename and payload are local format version 1. Future key changes
must migrate deliberately or request fresh approval. An inode replacement can
require reapproval even when the store UUID is unchanged. This is intentional.
The filesystem lease does not authenticate a peer or replace Keychain grants.
Normal startup, locator publication and signed host acceptance remain separate.

Source checked on 1 November 2026:
[Apple: NSStoreUUIDKey](https://developer.apple.com/documentation/coredata/nsstoreuuidkey).
The installed Darwin SDK defines F_GETPATH for the full path of an open descriptor.
