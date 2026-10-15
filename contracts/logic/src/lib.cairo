//! Pure logic of Grim World: state in, state out, no storage and no contract (ADR-0007, *The
//! layering is kept*). The rules of a tick live here, so that tests need no deployment and the
//! client can mirror them (SPK-4). It also holds what both domains share without either depending
//! on the other (ENG-01): identifiers and bounds, the wire format of actions, the snapshot and
//! results, the packing rules, the kinds of registry records and the calls between contracts.

/// The bounds of the MVP, and the layout of entity ids (M-5).
pub mod constants;
/// What belongs to no entity, scoped in traits: the table of `2^(x/40)`, the packing rules.
pub mod helpers;
/// The calls between contracts: results, entry, registry reads, randomness.
pub mod interface;
/// The world's registry records as models: regions, locations, gates, outlines (D-143).
pub mod models;
/// The snapshot of an adventurer taken at entry, and the tasks an instance reports.
pub mod snapshot;
/// The library classes (ENG-01 §1.3): the tick's, `TickLibrary`.
pub mod systems;
/// Identifiers, bounds and enums shared by the two domains.
pub mod types;
