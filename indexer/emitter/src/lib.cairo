//! The test emitter of the indexer (IDX-01a): `HubEmitter` and `MarketEmitter` emit, on demand, the
//! events of `Hub` and `Market` (docs/architecture/ENG-01-interfaces.md §5). The event structs are
//! `grimworld_persistent::events`, through a path dependency, never a copy; each contract's enum
//! has the game contract's variant names, so the first key is the same selector. Test networks
//! only: nothing here checks a caller or holds state.

pub mod hub;
pub mod market;
