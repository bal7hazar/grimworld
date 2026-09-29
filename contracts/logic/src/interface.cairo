//! The calls between contracts (docs/architecture/ENG-01-interfaces.md, *Boundaries*). They live
//! in the shared package so that neither domain's package depends on the other's (ADR-0007).

use starknet::ContractAddress;
use crate::snapshot::{Snapshot, TaskEntry};
use crate::types::{InstanceId, Outcome};

/// The results interface (ADR-0001, *Keeping the exit open*): what an instance hands to the
/// persistent domain, in **one call per transaction** that has any result (D-131). Bounds are
/// checked by the receiver: contributors ≤ 8, balances ≤ 8, equipment ≤ 3, tasks ≤ 16 and
/// only among the ids snapshotted at entry.
#[derive(Drop, Serde, Debug, PartialEq)]
pub struct Results {
    pub instance_id: InstanceId,
    /// The adventurers credited (M-4): every member who contributed; one in the MVP.
    pub contributors: Span<u32>,
    /// Experience for each contributor.
    pub experience: u32,
    pub gold: u64,
    /// `(item id, amount)` into the pack of the first contributor (design/07: loot goes straight
    /// to the inventory).
    pub balances: Span<(u32, u32)>,
    /// Equipment dropped, each an `ItemBase` of the persistent layout (unidentified: no modifier
    /// exists before identification, design/15).
    pub equipment: Span<felt252>,
    /// `(task id, increment)` for tasks snapshotted at entry (D-131).
    pub tasks: Span<(u32, u16)>,
    /// Facts the persistent domain records: bit 0 dungeon cleared, 1 trial passed, 2 Rift
    /// cleared, 3 zone entirely revealed, 4 a hub gate reached (unlock).
    pub facts: u32,
    /// The location the facts are about (the dungeon, the zone, the hub unlocked).
    pub location: u16,
    pub outcome: Outcome,
    /// Returned or Defeated: the hub the adventurers are in afterwards.
    pub hub: u16,
    /// Moved: the instance entered through the gate.
    pub next: InstanceId,
    /// The potions left in each belt slot, credited back to the first contributor's pack when the
    /// report closes its presence (Returned; Defeated per escalation E-15). Zero in an `Open` or
    /// `Moved` report: the reserve carries into the next instance. What was consumed is gone. The
    /// reserve was debited from the pack at entry (`Hub.enter`); two slots of the same item are
    /// debited and credited as their sum (ENG-01 fix loop 1, F-1).
    pub belt: [u8; 4],
}

/// Implemented by the persistent contract `Hub`; callable only by the registered `Instances`.
#[starknet::interface]
pub trait IResults<T> {
    fn report(ref self: T, results: Results);
    /// A collector's barter (design/15): its price comes from the pack, which only the persistent
    /// domain holds. `false` when the pack lacks it; nothing changes then.
    fn barter(ref self: T, adventurer_id: u32, collector: u16) -> bool;
}

/// Implemented by the ephemeral contract `Instances`; callable only by the registered `Hub`.
#[starknet::interface]
pub trait IInstanceEntry<T> {
    /// Creates an instance of the gate's destination at sequence 0, with the entry draw (Fate),
    /// in the adventurer's reusable slot; returns its id. Every member word is written for the new
    /// generation at clock 0: state from the snapshot (the belt's counts from the reserve); timers
    /// empty: `act_slot` 255 (no activation) and every deadline 0, stored `LIVE + 255`; effects and
    /// recharges empty, stored `LIVE` (F-12, F-14). Nothing of a previous instance carries (F-12).
    fn create(
        ref self: T,
        adventurer_id: u32,
        controller: ContractAddress,
        gate: u16,
        snapshot: Snapshot,
        tasks: Span<TaskEntry>,
    ) -> InstanceId;
    /// The account that controls an adventurer changed owner (ADR-0005, A-7) while it is inside.
    fn set_controller(ref self: T, adventurer_id: u32, controller: ContractAddress);
}

/// Implemented by `Registry`: content read by every contract (pillar 6). `records` reads several
/// records of one kind in one call: an invocation makes at most one call per kind it needs.
#[starknet::interface]
pub trait IRegistryRead<T> {
    fn record(self: @T, kind: u8, id: u32) -> Span<felt252>;
    fn records(self: @T, kind: u8, ids: Span<u32>) -> Span<felt252>;
    /// Records of several kinds in one call, in the order asked: what a `play` needs (castes,
    /// skills, pack templates, the location) costs one call per invocation, not one per kind.
    /// Returns the **content version** first (D-141, E-5), then the records: the version is a
    /// value of the registry's storage, raised by every changed record (`set_record`), that a batch
    /// is computed under and executed under (`play`'s `version`).
    fn bundle(self: @T, requests: Span<(u8, u32)>) -> (u32, Span<felt252>);
    /// The content version alone (the client's read before it computes a batch).
    fn content_version(self: @T) -> u32;
}

/// The randomness provider (ADR-0002): game code calls only this. The MVP's provider is
/// `TxHashFate`; version 1's is another class at another address, with the same call.
#[starknet::interface]
pub trait IFate<T> {
    /// The random word of `domain` for this transaction. One word per domain; a transaction that
    /// needs several values derives them as `poseidon(word, domain, index)` (ADR-0002, rule 2).
    fn fate(ref self: T, domain: felt252) -> felt252;
}
