#[starknet::interface]
pub trait IMark<T> {
    fn mark(ref self: T, value: u32);
}

#[dojo::contract]
pub mod mark {
    use dojo::model::ModelStorage;
    use spk5::models::Marker;
    use starknet::get_caller_address;
    use super::IMark;

    #[abi(embed_v0)]
    impl MarkImpl of IMark<ContractState> {
        fn mark(ref self: ContractState, value: u32) {
            let mut world = self.world(@"spk5");
            let owner = get_caller_address();
            world.write_model(@Marker { owner, value });
        }
    }
}
