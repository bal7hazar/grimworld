use origami_hexmap::helpers::geometry::GeometryTrait;

// `origami_hexmap` 1.8.0 builds on the game's compiler (Cairo 2.19) and its functions run from
// the game's own package.
#[test]
fn test_hexmap_distance() {
    // (3, 0) -> (2, 1) is one step; (0, 0) -> (0, 2) is two; a full row is six.
    assert(GeometryTrait::distance(7, 3, 9) == 1, 'adjacent not 1');
    assert(GeometryTrait::distance(7, 0, 14) == 2, 'two rows not 2');
    assert(GeometryTrait::distance(7, 7, 13) == 6, 'row not 6');
    assert(GeometryTrait::distance(7, 24, 24) == 0, 'same tile not 0');
    assert(GeometryTrait::distance(7, 9, 3) == 1, 'not symmetric');
}
