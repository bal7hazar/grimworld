//! The calls between contracts (docs/architecture/ENG-01-interfaces.md, *Boundaries*). They live
//! in the shared package so that neither domain's package depends on the other's (ADR-0007).

use starknet::ContractAddress;
use crate::models::chunk::Terrain;
use crate::snapshot::{Loadout, SnapshotWords, TaskEntry, Worn};
use crate::types::reveal::{Progress, Site};
use crate::types::tick::Content;
use crate::types::world::Words;
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

/// The bits of `Results.facts`.
pub mod facts {
    pub const DUNGEON_CLEARED: u32 = 0x1;
    pub const TRIAL_PASSED: u32 = 0x2;
    pub const RIFT_CLEARED: u32 = 0x4;
    pub const ZONE_REVEALED: u32 = 0x8;
    /// A hub gate reached: `Results.location` is the hub, unlocked for map travel (design/01).
    pub const HUB_REACHED: u32 = 0x10;
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
    /// generation at clock 0: the snapshot's three words as `Hub` stored them (D-168), state from
    /// them (the belt's counts from the reserve); timers
    /// empty: `act_slot` 255 (no activation) and every deadline 0, stored `LIVE + 255`; effects and
    /// recharges empty, stored `LIVE` (F-12, F-14). Nothing of a previous instance carries (F-12).
    fn create(
        ref self: T,
        adventurer_id: u32,
        controller: ContractAddress,
        gate: u16,
        snapshot: SnapshotWords,
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
    /// Returns the **content version** first (D-141, E-5): a value of the registry's storage,
    /// raised by every changed record (`set_record`), that a batch is computed under and executed
    /// under (`play`'s `version`). Then the **inputs version** (D-169): raised only by a changed
    /// record of a kind the snapshot's flattening reads, that a stored snapshot is computed under
    /// (`Hub.set_build`) and checked against (`Hub.enter`). The two are one slot, read once. Then
    /// the records.
    fn bundle(self: @T, requests: Span<(u8, u32)>) -> (u32, u32, Span<felt252>);
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

/// The world tick's library class (ENG-01 §1.3, CBT-02): `Instances` calls it through
/// `ITickLibraryLibraryDispatcher`, the class hash being its configuration.
#[starknet::interface]
pub trait ITickLibrary<T> {
    /// Runs `ticks` world ticks over the stored `words` with the batch's `content`, stopping after
    /// a tick that defeated the adventurer; returns the words.
    fn run(self: @T, words: Words, content: Content, ticks: u8) -> Words;
}

/// The snapshot's flattening as a library class (ENG-01 §1.3, D-168): `Hub.set_build` calls it
/// through `IFlattenLibraryLibraryDispatcher`, the class hash being its configuration.
#[starknet::interface]
pub trait IFlattenLibrary<T> {
    /// The snapshot's three packed words (`MemberStats`, `MemberBar`, `MemberKit`) of `loadout`
    /// and the items `worn`, whose distinct modifier `ids` have the `MODIFIER` `records`, one
    /// part each, in the same order (`SnapshotBuildTrait::words`); refuses what the flattening
    /// refuses.
    fn words(
        self: @T, loadout: Loadout, worn: Span<Worn>, ids: Span<u16>, records: Span<felt252>,
    ) -> (felt252, felt252, felt252);
}

/// The chunk reveal's library class (ENG-01 §1.3, ENG-05): `Instances` calls it through
/// `IRevealLibraryLibraryDispatcher`, the class hash being its configuration.
#[starknet::interface]
pub trait IRevealLibrary<T> {
    /// Reveals `chunks` (in order) of instance `instance_id` in the location `site`, from
    /// `progress`, with the terrain of every revealed neighbour in `known` (in a dungeon, of every
    /// revealed chunk)
    /// (`types::reveal::RevealTrait::reveal`): the progress after them, and the chunks revealed as
    /// `(chunk, terrain, features)`, their two words packed as stored (ENG-01 §3.2).
    fn reveal(
        self: @T,
        site: Site,
        progress: Progress,
        instance_id: felt252,
        known: Span<(u8, Terrain)>,
        chunks: Span<u8>,
    ) -> (Progress, Span<(u8, felt252, felt252)>);
}
