//! Pure logic of Grim World: state in, state out, no storage and no contract (ADR-0007, *The
//! layering is kept*). The rules of a tick live here, so that tests need no deployment and the
//! client can mirror them (SPK-4). It also holds what both domains share without either depending
//! on the other (ENG-01): identifiers and bounds, the wire format of actions, the snapshot and
//! results, the packing rules, the kinds of registry records and the calls between contracts.

/// The actions of a played batch and their wire format (one felt per batch).
pub mod actions;
/// The kinds of registry records and their size.
pub mod content;
/// The calls between contracts: results, entry, registry reads, randomness.
pub mod interface;
/// Packing into felts: two limbs, the `LIVE` bit, lanes, bitmaps.
pub mod packing;
/// The snapshot of an adventurer taken at entry, and the tasks an instance reports.
pub mod snapshot;
/// The rules of a tick: state in, state out.
pub mod tick;
/// Identifiers, bounds and enums shared by the two domains.
pub mod types;
