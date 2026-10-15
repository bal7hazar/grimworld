// The identifiers of `types` and the parts of each `content` kind. Packing's own tests are in
// `helpers/packing.cairo` (D-167); this one moves with `types` and `content` (ENG-R1c-2, PRs 3 and
// 4).
use grimworld_logic::types::content::{KindTrait, LAST_KIND};
use grimworld_logic::types::{goblin_entity, instance_id, instance_parts};

#[test]
// gas: raised, ENG-09: one more kind's parts asserted (25 and the last, 28)
#[available_gas(l2_gas: 13220)] // ceil(1.05 × 12590 measured)
fn test_identifiers() {
    let id = instance_id(7, 3);
    assert(id == 7 * 0x100000000 + 3, 'instance id');
    assert(instance_parts(id) == (7, 3), 'parts');
    assert(goblin_entity(0, 0) == 8, 'first goblin');
    assert(goblin_entity(224, 9) == 8 + 16 * 224 + 9, 'last goblin');
    assert(
        KindTrait::parts(2) == 2
            && KindTrait::parts(15) == 3
            && KindTrait::parts(25) == 1
            && KindTrait::parts(LAST_KIND) == 3,
        'parts per kind',
    );
}
