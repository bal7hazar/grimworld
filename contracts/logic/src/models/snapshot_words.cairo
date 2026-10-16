//! `SnapshotWords`, the snapshot as `Hub.enter` hands it to `Instances.create` (D-168): its three
//! words packed (`models::member_stats`, `member_bar`, `member_kit`) and the belt's counts.

/// The snapshot as `Hub.enter` hands it to `Instances.create` (D-168): the three words as
/// `SnapshotBuildTrait::words` packed them (`MemberStats`, `MemberBar`, `MemberKit`, `LIVE` set),
/// which `Hub.set_build` stored and `Instances` stores as they are, and the belt's counts.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct SnapshotWords {
    pub stats: felt252,
    pub bar: felt252,
    pub kit: felt252,
    pub belt_counts: [u8; 4],
}
