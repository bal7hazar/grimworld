//! Single access point to the storage of the persistent domain (ENG-01). Until ARC-06's store
//! takes over every access (D-143), it holds the typed access of the models that no word
//! arithmetic of `Hub` reads: the stored snapshot (CBT-02e, D-168), and the state that decides
//! whether it is stale, `Hub`'s rules epoch and `Registry`'s versions (CBT-02f, D-169), with the
//! two configuration values `set_contracts` compares to move the epoch.

use starknet::storage::{Mutable, StoragePath, StoragePointerReadAccess, StoragePointerWriteAccess};
use starknet::{ClassHash, ContractAddress};
use crate::models::rules_epoch::RulesEpoch;
use crate::models::snapshot::StoredSnapshot;
use crate::models::versions::Versions;

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

    /// `Hub.rules_epoch`, one slot; 0 at deployment. Read by `set_build`, `enter` and
    /// `set_contracts`.
    #[inline(always)]
    fn get_rules_epoch(path: StoragePath<RulesEpoch>) -> RulesEpoch {
        path.read()
    }

    /// Writes `Hub.rules_epoch` (`set_contracts`, when the configuration the flattening depends
    /// on changes). Untracked: no event (D-149).
    #[inline(always)]
    fn set_rules_epoch(path: StoragePath<Mutable<RulesEpoch>>, epoch: RulesEpoch) {
        path.write(epoch)
    }

    /// `Registry.versions`, one slot: the content and inputs versions; 0 at deployment. Read by
    /// `bundle`, `content_version` and `set_record`.
    #[inline(always)]
    fn get_versions(path: StoragePath<Versions>) -> Versions {
        path.read()
    }

    /// Writes `Registry.versions` (`set_record`, a changed record). Untracked: no event.
    #[inline(always)]
    fn set_versions(path: StoragePath<Mutable<Versions>>, versions: Versions) {
        path.write(versions)
    }

    /// A registered contract's address of `Hub`'s configuration, as `set_contracts` compares it.
    #[inline(always)]
    fn get_address(path: StoragePath<ContractAddress>) -> ContractAddress {
        path.read()
    }

    /// A class hash of `Hub`'s configuration (`flatten`), as `set_contracts` compares it.
    #[inline(always)]
    fn get_class_hash(path: StoragePath<ClassHash>) -> ClassHash {
        path.read()
    }
}
