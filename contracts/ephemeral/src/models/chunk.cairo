//! A revealed chunk: two felts under `(slot, chunk)`, both written at its reveal (ADR-0006,
//! D-136). Occupancy is not stored: it is the tiles of the goblins and adventurers in the window,
//! derived at each tick (ENG-01, *Chunks*). Layouts: docs/architecture/ENG-01-interfaces.md.
//!
//! Its two words are the models of `grimworld_logic::models::chunk` (ENG-05 Open question 4: the
//! reveal, the tick and the views read them without depending on `Instances`), packed by their
//! `StorePacking` there. The storage declares them as typed slots (`Stored<M>`, ENG-R1a's note 4):
//! the reveal's library returns them packed and `Instances` writes them as they are, the view
//! returns them as stored, and a path that needs a field reads the model (`Stored::model`).

pub use grimworld_logic::models::chunk::{
    Features, FeaturesStorePacking, Object, PackPlacement, Terrain, TerrainStorePacking,
};
use crate::helpers::stored::Stored;

/// The two consecutive slots of a revealed chunk, `Terrain`'s word then `Features`'.
#[derive(Copy, Drop, starknet::Store)]
pub struct Chunk {
    pub terrain: Stored<Terrain>,
    pub features: Stored<Features>,
}
