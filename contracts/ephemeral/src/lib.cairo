//! Grim World, ephemeral domain (ADR-0001, *Keeping the exit open*; ADR-0007): instance state.
//! Layering, from the outside in: systems, components, store, models, types, elements, helpers,
//! registries. No storage struct of this package holds a field of the persistent domain. No game
//! code yet.

/// Contracts: entrypoints, access control, nothing else.
pub mod systems;
/// Game logic, reusable across contracts (Starknet components).
pub mod components;
/// Single access point to storage.
pub mod store;
/// Storage structs: layout, packing, invariants (asserts).
pub mod models;
/// Enums dispatching to elements.
pub mod types;
/// One file per content behaviour (a skill effect, a caste profile).
pub mod elements;
/// Pure functions: bitmap, packer, seeder, math.
pub mod helpers;
/// Content as data, in storage: regions, locations, castes, skills, quests, loot, books.
pub mod registries;
