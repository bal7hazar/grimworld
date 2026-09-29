//! The kinds of registry records and their size in felts (docs/architecture/ENG-01-interfaces.md,
//! *Registries*). A record is `parts(kind)` felts under `(kind, id)`; ids are append-only
//! (design/01, rule 2), values may change. Core systems read these and never hard-code a content
//! id (pillar 6). The field layouts inside each record are in the document; ENG-03 writes them.

pub const REGION: u8 = 1;
pub const LOCATION: u8 = 2;
/// A zone's outline: id `location × 256 + 255` is its chunk set (a bitmap, bit `15 cy + cx`);
/// id `location × 256 + chunk` is the tile mask of a border chunk (ADR-0006, *Outlines*).
pub const OUTLINE: u8 = 3;
pub const GATE: u8 = 4;
/// The quotas of a location (ADR-0006, kind 2).
pub const QUOTAS: u8 = 5;
pub const SPAWN_TABLE: u8 = 6;
pub const PACK: u8 = 7;
pub const CASTE: u8 = 8;
pub const SKILL: u8 = 9;
pub const LOOT_TABLE: u8 = 10;
/// Ingredients, materials, potions, trophies, stillstone, heartstone, quest items, gold-less
/// goods: everything counted, not slotted.
pub const ITEM: u8 = 11;
/// Equipment bases (design/15).
pub const BASE: u8 = 12;
pub const MODIFIER: u8 = 13;
pub const ARMOR_SET: u8 = 14;
pub const BOOK: u8 = 15;
/// What counts toward a quiver task (the game side of a task, D-131).
pub const TASK: u8 = 16;
/// The game side of a quest: giver, rank, rewards, skills given at acceptance (design/06, 14).
pub const QUEST: u8 = 17;
pub const RANK: u8 = 18;
pub const RIFT_GRADE: u8 = 19;
pub const COLLECTOR: u8 = 20;
/// A hub's service offers: id `hub × 16 + service` (trainer, merchant, smith, armorer,
/// enchanter, alchemist).
pub const SHOP: u8 = 21;
pub const LANDMARK: u8 = 22;
/// The daily contracts a hub draws from (design/14).
pub const CONTRACT_POOL: u8 = 23;
/// An authored chunk placed by a quota (ADR-0006, *Set pieces*).
pub const SET_PIECE: u8 = 24;
/// A "distinct" counter of titles (design/13, T-2): what sets its bits.
pub const COUNTER: u8 = 25;
/// The last kind: kinds are 1 to `LAST_KIND`.
pub const LAST_KIND: u8 = 25;

/// Felts per record of each kind (index = kind; 0 is not a kind).
pub const PARTS: [u8; 26] = [
    0, 1, 2, 1, 1, 1, 1, 1, 2, 2, 2, 1, 2, 1, 1, 3, 1, 2, 1, 1, 1, 2, 1, 1, 2, 1,
];

/// Allocation (ENG-01 fix loop 1, F-8). **Sequential** kinds take ids 1, 2, 3 … in order: a new
/// id must be `last_id(kind) + 1`, and `last_id` is the highest written. **Composite** kinds take
/// ids built from other records (`OUTLINE`: `location × 256 + chunk`; `SHOP`: `hub × 16 +
/// service`) or given by quiver (`TASK`, `QUEST`: quiver's ids): any id whose parent exists;
/// `last_id` stays 0 for them. For every kind a record **exists** when its part 0 is not 0: its
/// writer sets `LIVE`
/// (bit 250) in part 0, so that a record whose fields are all 0 still exists.
pub fn is_sequential(kind: u8) -> bool {
    kind != OUTLINE && kind != SHOP && kind != TASK && kind != QUEST
}

/// Records one `records` or `bundle` call returns at most (ENG-01 §4.5): at most 3 parts each, so
/// a call reads at most 96 records' slots and, for `bundle`, the content version.
pub const MAX_READ: u32 = 32;

pub fn parts(kind: u8) -> u8 {
    assert(kind != 0 && kind <= LAST_KIND, 'registry: unknown kind');
    *PARTS.span()[kind.into()]
}

/// Criteria of a task (`TaskEntry.kind`, D-131).
pub const CRITERION_KILL_CASTE: u8 = 1;
pub const CRITERION_REACH_LANDMARK: u8 = 2;
pub const CRITERION_CLEAR_DUNGEON: u8 = 3;
pub const CRITERION_REVEAL_ZONE: u8 = 4;
pub const CRITERION_LOOT: u8 = 5;
pub const CRITERION_MINE: u8 = 6;
pub const CRITERION_ACTIVATE: u8 = 7;
