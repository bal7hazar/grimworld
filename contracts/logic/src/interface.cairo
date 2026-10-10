//! The calls between contracts (docs/architecture/ENG-01-interfaces.md, *Boundaries*). They live
//! in the shared package so that neither domain's package depends on the other's (ADR-0007).

use starknet::{ClassHash, ContractAddress};
use crate::actions::Action;
use crate::models::chunk::{Features, Terrain};
use crate::models::set_piece::SetPiece;
use crate::snapshot::{Loadout, SnapshotWords, TaskEntry, Worn};
use crate::types::action::Illegal;
use crate::types::executor::{Board, Cache, Carrier};
use crate::types::play::{Area, Classes, Done};
use crate::types::reveal::outline::Outline;
use crate::types::reveal::{Progress, Site};
use crate::types::tick::Content;
use crate::types::world::{Actor, Words};
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
    /// Runs `ticks` world ticks over the stored `words` with the batch's `content` on the tick's
    /// `board`, each carrier through `classes.executor` (route (c)), perception in process and
    /// step 2 through `classes.ai` (ENG-07), a trap through `classes.trap` (`level`, the location
    /// band's lower level), the chunk objects `ground` carried across them (Open question 3);
    /// stops after a tick that defeated the adventurer. Returns the words and the ground.
    fn ticks(
        self: @T,
        words: Words,
        content: Content,
        board: Board,
        classes: Classes,
        level: u8,
        ground: Array<(u8, Features)>,
        ticks: u8,
    ) -> (Words, Array<(u8, Features)>);
}

/// The adventurer's combat action as its own library class (D-233; design/19 §5.3, CBT-05b):
/// `TickLibrary`'s segment calls it through `IActionLibraryLibraryDispatcher` for an Attack, a
/// Skill or an Item only, the class hash being `Instances`' configuration.
#[starknet::interface]
pub trait IActionLibrary<T> {
    /// The adventurer's `action` (member 0) at the words' clock (§5.3): its legality, costs,
    /// facing and resolution through the executor's class `executor`, a trap placed in `ground`.
    /// Returns the words, the ground, and the action's tick cost, or why it is illegal (the words
    /// unchanged: the batch stops).
    fn act(
        self: @T,
        words: Words,
        content: Content,
        board: Board,
        executor: ClassHash,
        ground: Array<(u8, Features)>,
        action: Action,
    ) -> (Words, Array<(u8, Features)>, Result<u8, Illegal>);
}

#[starknet::interface]
pub trait ISegmentLibrary<T> {
    fn segment(
        self: @T,
        words: Words,
        content: Content,
        area: Area,
        classes: Classes,
        level: u8,
        ground: Array<(u8, Features)>,
        actions: Span<Action>,
        owed: u8,
        weight: u8,
    ) -> (Words, Array<(u8, Features)>, Done);
}

/// The goblins' acts as their own library class (ENG-07 Open question 1, candidate C): the tick's
/// rules (`TickLibrary`'s `Delegate`) call it through `IAiLibraryLibraryDispatcher` once a tick
/// for step 2, only on a tick where a goblin of the window is free to act (D-225), the class hash
/// being `Instances`' configuration.
#[starknet::interface]
pub trait IAiLibrary<T> {
    /// Step 2 over `words` (every member, then the awake set's goblins in their order, each awake)
    /// on `board`, `resolved` holding those that resolved in step 1 (bit `2^k` for the `k`-th) and
    /// `frozen` the window's tiles of the other living goblins (a bitmap of the window): each free
    /// goblin's act (`types::ai`), its carriers through the executor's class `executor`, a trap
    /// it enters through `trap` (`level`, the location band's lower level) with the chunk objects
    /// `ground`. Returns the words and the ground.
    fn act(
        self: @T,
        words: Words,
        content: Content,
        board: Board,
        executor: ClassHash,
        trap: ClassHash,
        ground: Array<(u8, Features)>,
        level: u8,
        frozen: felt252,
        listed: u8,
        resolved: u128,
    ) -> (Words, Array<(u8, Features)>);
}

/// A trap's trigger as its own library class (design/19 §5.11, CBT-05b, D-222): the move's owner
/// (ENG-07) calls it through `ITrapLibraryLibraryDispatcher` once an actor entered a tile holding
/// an unused trap, the class hash being `Instances`' configuration.
#[starknet::interface]
pub trait ITrapLibrary<T> {
    /// The entity `entrant` entered the window's `position` of `board`: the tile's unused trap in
    /// `ground` triggers if the entrant is a foe of its side, its payload through the executor with
    /// the entrant its only actor (`TrapTrait::trigger`); `level` is the location band's lower
    /// level (a terrain trap's source). Returns the words, the ground (the trap used) and whether
    /// it triggered.
    fn trigger(
        self: @T,
        words: Words,
        content: Content,
        board: Board,
        ground: Array<(u8, Features)>,
        entrant: u16,
        position: u8,
        level: u8,
    ) -> (Words, Array<(u8, Features)>, bool);
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

/// A location's quota hosts as a library class (ENG-01 §1.3, ENG-05, D-210), and since CBT-05g
/// (D-240) the reveals' site: `Instances` calls it through `IHostsLibraryLibraryDispatcher` once at
/// `create` (`enter`, which runs `hosts` in a zone with quotas or `floor` in a dungeon floor,
/// ENG-10b), `PlayLibrary` once a reveal in play (`reveal`), the class hash being its
/// configuration.
#[starknet::interface]
pub trait IHostsLibrary<T> {
    /// A reveal of `chunks` in play (CBT-05g, D-240): `destination`'s site read here (the registry
    /// at `registry`), its masks given `hosts` (one stored bitmap a quota, 0 for a quota with
    /// nothing left) or, in a dungeon floor, its stored `outline` (chunks, west, north); then
    /// `RevealLibrary`'s (`reveal`) `reveal` from `progress`, the stored one, whose result it
    /// returns.
    fn reveal(
        self: @T,
        registry: starknet::ContractAddress,
        reveal: starknet::ClassHash,
        destination: u16,
        location: crate::models::location::Location,
        entry_chunk: u8,
        entry_tile: u8,
        tasks: Span<crate::snapshot::TaskEntry>,
        hosts: Span<felt252>,
        outline: Option<(felt252, felt252, felt252)>,
        progress: crate::types::reveal::Progress,
        instance_id: felt252,
        known: Span<(u8, crate::models::chunk::Terrain)>,
        chunks: Span<u8>,
    ) -> (crate::types::reveal::Progress, Span<(u8, felt252, felt252)>);
    /// `create`'s entry reveal (CBT-05g, D-240): `destination`'s site read here, the progress of
    /// `entropy`; a zone's quota hosts (`hosts`) or a dungeon floor's outline and hosts (`floor`),
    /// drawn once; then `RevealLibrary`'s (`reveal`) `reveal` of `chunks`. Returns its progress and
    /// chunks, one host bitmap a quota (none in a zone without quotas) and a floor's outline.
    fn enter(
        self: @T,
        registry: starknet::ContractAddress,
        reveal: starknet::ClassHash,
        destination: u16,
        location: crate::models::location::Location,
        entry_chunk: u8,
        entry_tile: u8,
        tasks: Span<crate::snapshot::TaskEntry>,
        chunks: Span<u8>,
        entropy: felt252,
        instance_id: felt252,
    ) -> (
        crate::types::reveal::Progress,
        Span<(u8, felt252, felt252)>,
        Span<felt252>,
        Option<crate::types::reveal::outline::Outline>,
    );
    /// The host chunks of each of the 14 quotas of `plan` (`PlacementTrait::plan`) in the zone
    /// `zone` (its chunk set, 0 for its whole `width × height` rectangle), the location's set
    /// pieces in `pieces`, drawn from `seed` (`PlacementTrait::hosts`): one bitmap a quota, bit
    /// `15 cy + cx`; and `masks`, the masks of the chunks to reveal, each with the quotas its chunk
    /// hosts above the board (`PlacementTrait::with_hosts`).
    fn hosts(
        self: @T,
        zone: felt252,
        width: u8,
        height: u8,
        plan: (felt252, felt252),
        pieces: Span<(u16, SetPiece)>,
        masks: Span<(u8, felt252)>,
        seed: felt252,
    ) -> (Span<felt252>, Span<(u8, felt252)>);
    /// A dungeon floor at `create` (ENG-10b; ADR-0006 §3, *A dungeon floor's outline, fixed at
    /// entry*): its outline of `n` chunks entered at `entry` in the `width × height` rectangle,
    /// drawn from the instance's `entropy` (`OutlineTrait::draw`, seeded by
    /// `EntropyTrait::outline`); the host chunks of each quota of `plan` over it
    /// (`PlacementTrait::hosts`, seeded by `EntropyTrait::hosts`: the exit and the Heart first,
    /// among its farthest chunks); and the masks of `chunks`, the chunks the entry reveals, with
    /// the quotas each hosts above the board.
    fn floor(
        self: @T,
        entry: u8,
        n: u8,
        width: u8,
        height: u8,
        plan: (felt252, felt252),
        pieces: Span<(u16, SetPiece)>,
        chunks: Span<u8>,
        entropy: felt252,
        instance_id: felt252,
    ) -> (Outline, Span<felt252>, Span<(u8, felt252)>);
}

/// The chunk reveal's library class (ENG-01 §1.3, ENG-05): `Instances` calls it through
/// `IRevealLibraryLibraryDispatcher`, the class hash being its configuration.
#[starknet::interface]
pub trait IRevealLibrary<T> {
    /// Reveals `chunks` (in order) of instance `instance_id` in the location `site`, from
    /// `progress`, with the terrain of every revealed neighbour in `known`
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
    /// Reveals `chunks` of an authored zone (ENG-09, D-214, D-215; `types::reveal::authored`): each
    /// revealable one copied from its record in `records` (`ZONE_CHUNK`s, a chunk without one all
    /// wall), its quotas laid on `hosts` (one bitmap a quota, drawn at `create`), its spawn points'
    /// level and count drawn from the chunk's own word. `HostsLibrary` reads the site and calls it.
    fn authored(
        self: @T,
        site: Site,
        progress: Progress,
        instance_id: felt252,
        records: Span<(u8, crate::models::zone_chunk::ZoneChunk)>,
        hosts: Span<felt252>,
        chunks: Span<u8>,
    ) -> (Progress, Span<(u8, felt252, felt252)>);
}

/// The executor as its own library class (CBT-05a, route (c)): one call a carrier, the words of the
/// actors it can reach and the batch's content in; the words out, and whether a `TRAP` carrier's
/// guard held (its placement is CBT-05b's, §5.11).
#[starknet::interface]
pub trait IExecutorLibrary<T> {
    fn execute(
        self: @T,
        words: Words,
        content: Content,
        board: Board,
        cache: Cache,
        source: Actor,
        carrier: Carrier,
        address: u16,
        t: u32,
    ) -> (Words, Cache, bool);
}
