//! Identifiers, bounds and enums shared by the two domains and the client
//! (docs/architecture/ENG-01-interfaces.md). The order of every enum's variants is frozen: it is
//! their encoding in calldata and events.

/// The enumerations of combat that are not an entry's own fields (design/19, CBT-01).
pub mod combat;
/// The effect entry and its enumerations (design/19 §2, §3, CBT-01).
pub mod effect;
/// Passive effects (design/19 §4, CBT-01).
pub mod passive;
/// The state and content a world tick reads and writes (CBT-02).
pub mod tick;

/// An instance id: `slot × 2^32 + generation`. The slot is a reusable key of the ephemeral
/// contract's storage (M-1: instance state is keyed by it, never by an adventurer id); the
/// generation tells this instance from every earlier one of the same slot.
pub type InstanceId = u64;

const TWO_POW_32: u64 = 0x100000000;

pub fn instance_id(slot: u32, generation: u32) -> InstanceId {
    slot.into() * TWO_POW_32 + generation.into()
}

/// `(slot, generation)` of an instance id.
pub fn instance_parts(id: InstanceId) -> (u32, u32) {
    let (slot, generation) = DivRem::div_rem(id, TWO_POW_32.try_into().unwrap());
    (slot.try_into().unwrap(), generation.try_into().unwrap())
}

// Bounds of the MVP (design/02 *Simulation budget*, *Size*; D-131; D-135; ENG-01).

/// Actions in one `play` (design/02).
pub const MAX_ACTIONS: u8 = 10;
/// Weight of one `play`: `Σ max(1, ticks) + 2 × chunks revealed` (design/02).
pub const MAX_WEIGHT: u8 = 10;
/// Chunks revealed by one action (design/02).
pub const MAX_REVEAL: u8 = 3;
/// Awake goblins at a tick (design/02).
pub const MAX_AWAKE: u8 = 8;
/// Task ids an instance snapshots at entry and reports (D-131).
pub const MAX_TASKS: u8 = 16;
/// Adventurers in one instance (M-3). One in the MVP.
pub const MAX_MEMBERS: u8 = 8;
/// Quests an adventurer holds (D-135: 3 active and one contract).
pub const MAX_HELD_QUESTS: u8 = 4;
/// Chunks of a location: a grid of 15 × 15 chunks, index `15 cy + cx` (ADR-0006).
pub const MAX_CHUNKS: u8 = 225;
/// Chunk side, in tiles (ADR-0006).
pub const CHUNK_SIDE: u8 = 15;
/// Packs placed in one chunk, and goblins in one pack (ENG-01; design/05, design/18).
pub const MAX_PACKS_PER_CHUNK: u8 = 2;
pub const MAX_PACK_SIZE: u8 = 5;
/// Objects placed in one chunk: chests, veins, nodes, traps, collectors, landmarks (ENG-01).
pub const MAX_OBJECTS_PER_CHUNK: u8 = 3;
/// Goblins displaced from their spawn, alive or dead and not looted, at once in an instance: the
/// roster, four pages of fifteen (ENG-01, E-2). It is also how a view finds remains lying away
/// from their spawn chunk (F-6).
pub const MAX_ROSTER: u8 = 60;
pub const ROSTER_PAGES: u8 = 4;
/// No deadline passes this: deadlines are stored in 28 bits (ENG-01, E-4).
pub const MAX_CLOCK: u32 = 0xFFFFFFF;
/// The longest duration, recharge or activation the registry may hold (a `u16` of ticks).
pub const MAX_DURATION: u32 = 0xFFFF;
/// An action runs only while `clock ≤ LAST_TICK`: then every deadline it can set,
/// `clock + ticks run + a duration`, stays at or below `MAX_CLOCK` (ENG-01, E-4).
pub const LAST_TICK: u32 = MAX_CLOCK - MAX_DURATION - MAX_WEIGHT_TICKS;
/// The world ticks one batch can run (weight 10).
pub const MAX_WEIGHT_TICKS: u32 = 10;
/// Chunks per page of `instance_region` (a node's call limits, design/02).
pub const REGION_PAGE: u8 = 16;

/// Entity ids inside an instance (M-5): members are `0 .. MAX_MEMBERS`, goblins
/// `FIRST_GOBLIN + GOBLINS_STRIDE × chunk + k`, `k` below 10 (two packs of five) in the chunk
/// where the goblin spawned.
pub const FIRST_GOBLIN: u16 = 8;
pub const GOBLINS_STRIDE: u16 = 16;

pub fn goblin_entity(chunk: u8, k: u8) -> u16 {
    FIRST_GOBLIN + GOBLINS_STRIDE * chunk.into() + k.into()
}

/// A global tile of a location, `x + 256 y` (x and y below 225).
pub type Tile = u16;

/// Why a batch stopped (`BatchPlayed.stop`, design/02).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Stop {
    /// Every action ran.
    None,
    /// The sequence differs: nothing ran.
    Sequence,
    /// An action was illegal in the state it met.
    Invalid,
    /// The weight would pass 10.
    Weight,
    /// The adventurer was defeated by an action of the batch.
    Defeated,
    /// The instance is closed (or the id is of an earlier generation): nothing ran.
    Closed,
    /// The content version differs from the one the batch was computed under: nothing ran, the
    /// client reloads the content and computes again (D-141, E-5).
    Version,
}

/// Why a standalone action was refused before any draw (`Refused.reason`, design/02).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Refusal {
    /// The sequence differs.
    Sequence,
    /// The instance is closed, or the id is of an earlier generation.
    Closed,
    /// The adventurer is not in this instance, or is defeated.
    Absent,
    /// Not on or next to the target, or not in reach.
    Reach,
    /// The target is not there any more (looted, opened, mined).
    Gone,
    /// The gate is not reachable or its requirements are not met.
    Gate,
    /// The Red Rift is sealed: no travel back (design/17).
    Sealed,
    /// The collector's price is not in the pack.
    Price,
    /// The content version differs from the one the action was computed under: refused before any
    /// tick, nothing changes; the client reloads the content (D-141, E-5).
    Version,
}

/// How an instance ended, or that it goes on (`InstanceClosed.outcome`, results interface).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Outcome {
    /// Still open: results of a transaction inside the instance.
    Open,
    /// Walked into a hub gate or travelled back (D-04).
    Returned,
    /// Health reached 0 (D-04).
    Defeated,
    /// Left through a gate to another location: a new instance was entered.
    Moved,
}

/// The kind of a chunk for the window and for `instance_region` (design/02, D-134, D-136).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum ChunkKind {
    /// The margin around a location, or outside a zone's outline: never stored.
    Void,
    /// Inside the location, not yet revealed: wall in the window, never read.
    Unrevealed,
    /// Revealed in this instance: stored.
    Revealed,
}

/// A thing a Fate or gate action targets: a goblin's remains by entity id, or an object by tile.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Target {
    Entity: u16,
    Tile: Tile,
}
