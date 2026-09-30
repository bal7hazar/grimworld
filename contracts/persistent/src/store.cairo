//! Single access point to the storage of the persistent domain (ENG-01). Until ARC-06's store
//! takes over every access (D-143), it holds the typed access of the models that no word
//! arithmetic of `Hub` reads: the stored snapshot (CBT-02e, D-168).

use starknet::storage::{Mutable, StoragePath, StoragePointerReadAccess, StoragePointerWriteAccess};
use crate::models::snapshot::StoredSnapshot;

#[generate_trait]
pub impl StoreImpl of StoreTrait {
    /// The snapshot stored for an adventurer (`Hub.snapshots[adventurer]`, three slots), read as
    /// its model; a slot never written reads 0 (`StoredSnapshotAssert::assert_fresh`). Its reader
    /// is `enter`, whose path is mutable.
    #[inline(always)]
    fn get_snapshot(path: StoragePath<Mutable<StoredSnapshot>>) -> StoredSnapshot {
        path.read()
    }

    /// Writes the three words of `snapshot` (`StoredSnapshotTrait::new`). Untracked: no event
    /// (D-149).
    #[inline(always)]
    fn set_snapshot(path: StoragePath<Mutable<StoredSnapshot>>, snapshot: StoredSnapshot) {
        path.write(snapshot)
    }
}
