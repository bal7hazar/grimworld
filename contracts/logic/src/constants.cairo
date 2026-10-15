//! Bounds of the MVP shared by the two domains and the client (design/02 *Simulation budget*,
//! *Size*; D-131; D-135; ENG-01), and the layout of entity ids inside an instance (M-5).

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
