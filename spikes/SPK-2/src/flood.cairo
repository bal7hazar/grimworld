use origami_hexmap::helpers::layout::LayoutTrait;

pub fn probe() -> felt252 {
    let (_, interior) = LayoutTrait::with_interior(15, 16);
    interior
}
