//! Grim World contracts. Layering, from the outside in: systems, components, store, models,
//! types, elements, helpers, registries. Two domains, never mixed: persistent (`grimworld`)
//! and ephemeral (`grimworld_instance`), see contracts/README.md.

/// Thin contracts: entrypoints, access control, nothing else.
pub mod systems;
/// Game logic, reusable across systems.
pub mod components;
/// Single access point to the models.
pub mod store;
/// State and invariants (asserts) per model, split by domain.
pub mod models;
/// Enums dispatching to elements.
pub mod types;
/// One file per content behaviour (a skill effect, a caste profile).
pub mod elements;
/// Pure functions: bitmap, packer, seeder, math.
pub mod helpers;
/// Content as data: regions, locations, castes, skills, quests, loot, books.
pub mod registries;
