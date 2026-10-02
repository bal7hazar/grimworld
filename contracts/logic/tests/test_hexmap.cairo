use hexx::board::geometry::GeometryTrait;

// `hexx` 0.1.0-rc.1, the takeover of `origami_hexmap` 1.8.0 (D-173), builds on the game's compiler
// (Cairo 2.19) and its functions run from the game's own package, with 1.8.0's results.
#[test]
#[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
fn test_hexmap_distance() {
    // (3, 0) -> (2, 1) is one step; (0, 0) -> (0, 2) is two; a full row is six.
    assert(GeometryTrait::distance(7, 3, 9) == 1, 'adjacent not 1');
    assert(GeometryTrait::distance(7, 0, 14) == 2, 'two rows not 2');
    assert(GeometryTrait::distance(7, 7, 13) == 6, 'row not 6');
    assert(GeometryTrait::distance(7, 24, 24) == 0, 'same tile not 0');
    assert(GeometryTrait::distance(7, 9, 3) == 1, 'not symmetric');
}
