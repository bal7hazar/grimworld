// SPK-5b throwaway: one stored value, one entrypoint writing it, one event, one view.
#[starknet::interface]
pub trait IMark<T> {
    fn mark(ref self: T, value: u32);
    fn get(self: @T) -> u32;
}

#[starknet::contract]
pub mod Mark {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        value: u32,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Marked: Marked,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Marked {
        #[key]
        pub owner: ContractAddress,
        pub value: u32,
    }

    #[abi(embed_v0)]
    impl MarkImpl of super::IMark<ContractState> {
        fn mark(ref self: ContractState, value: u32) {
            self.value.write(value);
            self.emit(Marked { owner: get_caller_address(), value });
        }

        fn get(self: @ContractState) -> u32 {
            self.value.read()
        }
    }
}
