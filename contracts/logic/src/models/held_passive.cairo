//! `HeldPassive`, a passive the build holds, as the flattening reads it (design/20 §1.2): the
//! items worn give them (`models::worn`), the flattening sums them (`models::build`).

use crate::types::passive::{Passive, Source};

/// A passive the build holds (design/20 §1.2). Its value is `passive.max`: a benefit's rolled
/// value (the caller writes the roll in), a cost's fixed one. `instance` numbers its source: the
/// passives of one instance are one modifier on one item (its benefit and cost), or one set bonus.
/// `modifier` is the `MODIFIER` record's id (0 for a set bonus): health runes of one id count
/// once (FX-43, D-157 D).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct HeldPassive {
    pub passive: Passive,
    pub source: Source,
    pub instance: u8,
    pub modifier: u32,
    /// A modifier's benefit, not its cost; a set bonus is a benefit.
    pub benefit: bool,
    /// The armor piece its item is worn on (`base::slot::CHEST` … `FEET`) for an insignia, which
    /// bounds its health (DS-23); 0 for every other source.
    pub piece: u8,
}
