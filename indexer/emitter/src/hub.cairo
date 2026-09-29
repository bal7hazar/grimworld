/// Emits the five events of `Hub`, one per call, with the arguments as fields.
#[starknet::interface]
pub trait IHubEmitter<T> {
    fn adventurer_located(ref self: T, hub: u16, adventurer: u32);
    fn title_displayed(ref self: T, adventurer: u32, title: u16, tier: u8);
    fn trial_passed(ref self: T, adventurer: u32, rank: u8, first_attempt: bool);
    fn dungeon_cleared(ref self: T, adventurer: u32, dungeon: u16);
    fn rank_reached(ref self: T, adventurer: u32, rank: u8);
}

#[starknet::contract]
pub mod HubEmitter {
    use grimworld_persistent::events::{
        AdventurerLocated, DungeonCleared, RankReached, TitleDisplayed, TrialPassed,
    };

    #[storage]
    struct Storage {}

    /// The variants of `Hub::Event`, in its order, over its event structs: the first key is the
    /// selector of the variant's name, as in `Hub`.
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        AdventurerLocated: AdventurerLocated,
        TitleDisplayed: TitleDisplayed,
        TrialPassed: TrialPassed,
        DungeonCleared: DungeonCleared,
        RankReached: RankReached,
    }

    #[abi(embed_v0)]
    impl HubEmitterImpl of super::IHubEmitter<ContractState> {
        fn adventurer_located(ref self: ContractState, hub: u16, adventurer: u32) {
            self.emit(AdventurerLocated { hub, adventurer });
        }

        fn title_displayed(ref self: ContractState, adventurer: u32, title: u16, tier: u8) {
            self.emit(TitleDisplayed { adventurer, title, tier });
        }

        fn trial_passed(ref self: ContractState, adventurer: u32, rank: u8, first_attempt: bool) {
            self.emit(TrialPassed { adventurer, rank, first_attempt });
        }

        fn dungeon_cleared(ref self: ContractState, adventurer: u32, dungeon: u16) {
            self.emit(DungeonCleared { adventurer, dungeon });
        }

        fn rank_reached(ref self: ContractState, adventurer: u32, rank: u8) {
            self.emit(RankReached { adventurer, rank });
        }
    }
}
