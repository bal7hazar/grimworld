//! A revealed chunk: two felts under `(slot, chunk)`, both written at its reveal (ADR-0006,
//! D-136). Occupancy is not stored: it is the tiles of the goblins and adventurers in the window,
//! derived at each tick (ENG-01, *Chunks*). Layouts: docs/architecture/ENG-01-interfaces.md.
//!
//! Its two words are the models of `grimworld_logic::models::chunk` (ENG-05 Open question 4: the
//! reveal, the tick and the views read them without depending on `Instances`), packed by their
//! `StorePacking` there; this struct only puts them in two consecutive slots.

pub use grimworld_logic::models::chunk::{
    Features, FeaturesStorePacking, Object, PackPlacement, Terrain, TerrainStorePacking,
};

/// The two consecutive slots of a revealed chunk.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Chunk {
    pub terrain: Terrain,
    pub features: Features,
}
