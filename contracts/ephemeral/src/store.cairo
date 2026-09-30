//! Single access point to the storage of the ephemeral domain (ENG-01). Until ARC-06's store
//! takes over every access (D-143), it holds the typed access that writes a member's snapshot as
//! `Hub` stored it (CBT-02e, D-168).

use grimworld_logic::snapshot::SnapshotWords;
use starknet::SyscallResultTrait;
use starknet::storage::{Mutable, StorageAsPointer, StoragePath};
use starknet::storage_access::Store;
use crate::models::member::{Member, STATS_WORD};

/// `Member`'s `bar` and `kit`, the two slots after `stats` (`Store` layout: field `i` at offset
/// `i`).
const BAR_WORD: u8 = STATS_WORD + 1;
const KIT_WORD: u8 = STATS_WORD + 2;

#[generate_trait]
pub impl StoreImpl of StoreTrait {
    /// A member's `stats`, `bar` and `kit`: the snapshot's three words as `Hub` stored them,
    /// packed by the flattening (`FlattenLibrary`), so written as they are, without unpacking.
    fn set_snapshot(member: StoragePath<Mutable<Member>>, snapshot: @SnapshotWords) {
        let base = member.as_ptr().__storage_pointer_address__;
        Store::<felt252>::write_at_offset(0, base, STATS_WORD, *snapshot.stats).unwrap_syscall();
        Store::<felt252>::write_at_offset(0, base, BAR_WORD, *snapshot.bar).unwrap_syscall();
        Store::<felt252>::write_at_offset(0, base, KIT_WORD, *snapshot.kit).unwrap_syscall();
    }
}
