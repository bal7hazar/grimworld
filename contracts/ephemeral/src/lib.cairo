//! Grim World, ephemeral domain (ADR-0001, *Keeping the exit open*; ADR-0007): instance state.
//! Layering, from the outside in: systems, components, store, models, types, elements, helpers,
//! registries. No storage struct of this package holds a field of the persistent domain. No game
//! code yet.

/// Game logic, reusable across contracts (Starknet components).
pub mod components;
/// One file per content behaviour (a skill effect, a caste profile).
pub mod elements;
/// Pure functions: bitmap, packer, seeder, math.
pub mod helpers;
/// Storage structs: layout, packing, invariants (asserts).
pub mod models;
/// Measurement probes of ENG-01 (reuse of a key, a call between contracts); never deployed.
pub mod probes;
/// Content as data, in storage: regions, locations, castes, skills, quests, loot, books.
pub mod registries;
/// Single access point to storage.
pub mod store;
/// Contracts: entrypoints, access control, nothing else.
pub mod systems;
/// Enums dispatching to elements.
pub mod types;
