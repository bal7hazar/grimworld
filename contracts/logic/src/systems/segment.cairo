//! Variant: the segment as its own library class, called once a segment by PlayLibrary.
#[starknet::contract]
pub mod SegmentLibrary {
    use core::num::traits::Zero;
    use crate::actions::Action;
    use crate::interface::ISegmentLibrary;
    use crate::models::chunk::Features;
    use crate::types::executor::{BoardTrait, Delegate};
    use crate::types::play::{Area, Classes, Done, SegmentTrait};
    use crate::types::tick::Content;
    use crate::types::window::WindowTrait;
    use crate::types::world::{Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl SegmentLibraryImpl of ISegmentLibrary<ContractState> {
        fn segment(
            self: @ContractState,
            words: Words,
            content: Content,
            area: Area,
            classes: Classes,
            level: u8,
            ground: Array<(u8, Features)>,
            actions: Span<Action>,
            owed: u8,
            weight: u8,
        ) -> (Words, Array<(u8, Features)>, Done) {
            let (mut world, sheets, index) = words.indexed(@content);
            let mut rules = Delegate {
                board: BoardTrait::new(WindowTrait::new(0), 0, 0),
                cache: Default::default(),
                executor: classes.executor,
                content,
                index,
                placed: array![],
                ground,
                ai: classes.ai,
                trap: classes.trap,
                level,
                frozen: 0,
                listed: 0,
            };
            let _ = Zero::<felt252>::zero();
            let done = SegmentTrait::run(
                ref world, @sheets, ref rules, @area, @classes, actions, owed, weight,
            );
            (world.store(), rules.ground, done)
        }
    }
}
