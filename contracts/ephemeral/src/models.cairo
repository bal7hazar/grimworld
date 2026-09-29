//! Storage records of the ephemeral domain: layout, packing, invariants (ENG-01). Every record is
//! keyed by an instance slot (M-1), except `Placement`, the adventurer's reference to its
//! instance. None holds a field of the persistent domain; the member's snapshot is a copy taken at
//! entry (ADR-0001).

/// A revealed chunk: terrain and placements.
pub mod chunk;
/// A goblin that left its first state.
pub mod goblin;
/// The instance's header, quotas, and an adventurer's placement.
pub mod instance;
/// An adventurer inside an instance.
pub mod member;
