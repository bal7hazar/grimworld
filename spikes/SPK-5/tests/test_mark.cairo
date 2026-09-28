use dojo::model::ModelStorage;
use dojo::world::WorldStorageTrait;
use dojo_snf_test::{
    ContractDef, ContractDefTrait, NamespaceDef, TestResource, WorldStorageTestTrait,
    get_default_caller_address, set_caller_address, spawn_test_world,
};
use spk5::models::Marker;
use spk5::systems::{IMarkDispatcher, IMarkDispatcherTrait};

fn namespace_def() -> NamespaceDef {
    NamespaceDef {
        namespace: "spk5",
        resources: [TestResource::Model("Marker"), TestResource::Contract("mark")].span(),
    }
}

fn contract_defs() -> Span<ContractDef> {
    [
        ContractDefTrait::new(@"spk5", @"mark")
            .with_writer_of([dojo::utils::bytearray_hash(@"spk5")].span()),
    ]
        .span()
}

#[test]
#[available_gas(l2_gas: 5105383)] // ceil(1.05 × 4862269 measured)
fn test_mark_writes_the_model() {
    let caller = get_default_caller_address();
    let mut world = spawn_test_world([namespace_def()].span());
    world.sync_perms_and_inits(contract_defs());

    let (mark_address, _) = world.dns(@"mark").unwrap();
    set_caller_address(caller);
    IMarkDispatcher { contract_address: mark_address }.mark(42);

    let marker: Marker = world.read_model(caller);
    assert(marker.value == 42, 'marker not written');
}
