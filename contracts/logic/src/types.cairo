//! Identifiers and enums shared by the two domains and the client
//! (docs/architecture/ENG-01-interfaces.md); their bounds are in `constants`. The order of every
//! enum's variants is frozen: it is their encoding in calldata and events.

/// The adventurer's action between two ticks: legality, costs, facing, resolution (design/19 §5.3,
/// CBT-05b).
pub mod action;
/// The goblins' acts: step 2 of the tick, one hook for the step (ENG-07).
pub mod ai;
/// The actions of a played batch and their wire format (one felt per batch).
pub mod batch;
/// The enumerations of combat that are not an entry's own fields (design/19, CBT-01).
pub mod combat;
/// The kinds of registry records and their size.
pub mod content;
/// The effect entry and its enumerations (design/19 §2, §3, CBT-01).
pub mod effect;
/// The executor: one layer owns a carrier's entries (design/19 §5.14, CBT-05a).
pub mod executor;
/// One hit: block, evasion, armor, damage (design/19 §5.5 steps 1–4, §5.6, CBT-03a).
pub mod hit;
/// Instance ids and entity ids, made and read (M-1, M-5).
pub mod identifier;
/// What a source adds to the conditions it inflicts (design/19 §5.7, CBT-04).
pub mod infliction;
/// Passive effects (design/19 §4, CBT-01).
pub mod passive;
/// A segment of a played batch: the actions in order, the moves, the window (ENG-07).
pub mod play;
/// Profession ids, and those a player may choose at creation.
pub mod profession;
/// The chunk reveal engine: generation with margins, edges, the cut, quotas and placement
/// (ENG-05, ADR-0006).
pub mod reveal;
/// The state and content a world tick reads and writes (CBT-02).
pub mod tick;
/// Traps: placing one, triggering one (design/19 §5.11, CBT-05b).
pub mod trap;
/// The game's geometry on the window: sight, reach, arcs, facing, shapes (ENG-02).
pub mod window;
/// The world of a tick's library call, and the pipeline (CBT-02).
pub mod world;

/// An instance id: `slot × 2^32 + generation`. The slot is a reusable key of the ephemeral
/// contract's storage (M-1: instance state is keyed by it, never by an adventurer id); the
/// generation tells this instance from every earlier one of the same slot.
pub type InstanceId = u64;

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
