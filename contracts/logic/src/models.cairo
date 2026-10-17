pub mod armor_set;
pub mod base;
/// A bridge of an authored zone, `BRIDGE` (D-217, D-227; ENG-09).
pub mod bridge;
/// The flattening: a build and the passives it holds into the snapshot's three words (D-160).
pub mod build;
/// The candidate chunks of an authored zone's quotas, `CANDIDATES` (D-215; ENG-09).
pub mod candidates;
pub mod caste;
/// The words of a revealed chunk (ENG-05): terrain, packs, objects.
pub mod chunk;
pub mod gate;
/// A goblin in a world tick (CBT-02).
pub mod goblin;
/// A passive the build holds, as the flattening reads it (design/20 §1.2).
pub mod held_passive;
/// The Registry's records, and the structs that still sit with them (ruling 10), in one file; every
/// other model has its own file, with its checks and errors (D-143).
pub mod index;
pub mod item;
/// A profession's creation kit, `KIT` (D-309).
pub mod kit;
/// What the flattening reads of a build besides its passives.
pub mod loadout;
pub mod location;
/// A member in a world tick (CBT-02).
pub mod member;
/// The member's second snapshot word: the skill bar and the passives read at each hit or cast.
pub mod member_bar;
/// The member's third snapshot word: the belt and the equipment's modifiers.
pub mod member_kit;
/// The member's first snapshot word: what the build and the equipment give.
pub mod member_stats;
pub mod modifier;
pub mod outline;
/// A pack template, `PACK` (ENG-05).
pub mod pack;
/// A location's quotas, `QUOTAS` (ENG-05).
pub mod quotas;
pub mod region;
/// An authored chunk, `SET_PIECE` (ENG-05).
pub mod set_piece;
pub mod skill;
/// The snapshot an instance takes of an adventurer at entry: its three words and the belt's counts.
pub mod snapshot;
/// The snapshot's three words packed, as `Instances.create` receives them (D-168).
pub mod snapshot_words;
/// A location's spawn table, `SPAWN_TABLE` (ENG-05).
pub mod spawn_table;
/// The tasks an instance reports, four to a stored page (D-131).
pub mod task;
/// An item worn, as `Hub.set_build` reads it, and the passives the worn items hold.
pub mod worn;
/// One chunk of an authored zone, `ZONE_CHUNK` (D-214, D-215; ENG-09).
pub mod zone_chunk;
