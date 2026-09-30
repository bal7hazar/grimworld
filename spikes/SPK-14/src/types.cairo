//! The inputs of generation, shared by the rectangle and the hexagon (SPK-7's).

/// A location's biome (design/18 *Biomes*), SPK-7's parameters.
///
/// | Biome | Base | Born / survives |
/// |---|---|---|
/// | Meadow | 5/8: `a \| (b & c)` | 4+ / 3+ |
/// | Forest | 5/8: `a \| (b & c)` | 4+ / 4+ |
/// | Cave | 1/2: `a` | 5+ / 4+ |
/// | Ruin | 3/8: `a & (b \| c)` | 4+ / 4+ |
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Biome {
    Meadow,
    Forest,
    Cave,
    Ruin,
}

/// One side of a chunk at generation.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Side {
    /// No generated neighbour: 1 or 2 openings are drawn, then frozen (D-22).
    Open,
    /// The border of the location: closed.
    Border,
    /// A generated neighbour, its terrain (walkable tiles): its facing side is copied.
    Copy: felt252,
}

/// The four sides of a rectangle (SPK-7): East is `x - 1`, West `x + 1`, South `y - 1`, North
/// `y + 1`.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct RectSides {
    pub east: Side,
    pub west: Side,
    pub south: Side,
    pub north: Side,
}

/// The six sides of a hexagon, named by the lattice step of the neighbour they face: `minus_u`
/// row 0, `plus_u` row 16, `plus_r` q = 18, `minus_r` q = 0, `plus_ur` q + r = 26, `minus_ur`
/// q + r = 8.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct HexSides {
    pub minus_u: Side,
    pub plus_u: Side,
    pub plus_r: Side,
    pub minus_r: Side,
    pub plus_ur: Side,
    pub minus_ur: Side,
}
