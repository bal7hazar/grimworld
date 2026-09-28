use dojo_snf_test::{NamespaceDef, spawn_test_world};

fn namespace_defs() -> Span<NamespaceDef> {
    [
        NamespaceDef { namespace: "grimworld", resources: [].span() },
        NamespaceDef { namespace: "grimworld_instance", resources: [].span() },
    ]
        .span()
}

#[test]
#[available_gas(l2_gas: 1852027)] // ceil(1.05 × 1763835 measured)
fn test_world_spawns_with_both_domains() {
    let _world = spawn_test_world(namespace_defs());
}
