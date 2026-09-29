//! The checks of `Results` at the hub (docs/architecture/ENG-01-interfaces.md §4.5, §6). `report`
//! settles what the persistent models hold today: experience, gold, balances, the belt's reserve
//! (credited back when a report closes the member's presence, on return and on defeat: D-141,
//! E-15), the placement and a hub reached. It refuses what has no model yet rather than drop it:
//! equipment drops (the pack's capacity, design/15), task increments (quiver's quests are not
//! embedded, E-14), the facts other than a hub reached (the "distinct" counters, the Rift board,
//! trials). ENG-06's report escalates each.

use grimworld_logic::interface::{Results, facts};
use grimworld_logic::types::{MAX_MEMBERS, Outcome};

/// Balances one report carries at most (ENG-01 §4.5).
pub const MAX_BALANCES: u32 = 8;

pub mod errors {
    pub const CONTRIBUTORS: felt252 = 'results: contributors';
    pub const BALANCES: felt252 = 'results: balances';
    pub const EQUIPMENT: felt252 = 'results: equipment not settled';
    pub const TASKS: felt252 = 'results: tasks not settled';
    pub const FACTS: felt252 = 'results: facts not settled';
    /// A belt carried by a report that does not close the member's presence.
    pub const BELT: felt252 = 'results: belt';
}

#[generate_trait]
pub impl ResultsImpl of ResultsTrait {
    /// Whether the report closes the member's presence: the belt's reserve comes back then.
    #[inline(always)]
    fn closes(self: @Results) -> bool {
        *self.outcome == Outcome::Returned || *self.outcome == Outcome::Defeated
    }
}

#[generate_trait]
pub impl ResultsAssert of ResultsAssertTrait {
    fn assert_settled(self: @Results) {
        let contributors = (*self.contributors).len();
        assert(contributors != 0 && contributors <= MAX_MEMBERS.into(), errors::CONTRIBUTORS);
        assert((*self.balances).len() <= MAX_BALANCES, errors::BALANCES);
        assert((*self.equipment).len() == 0, errors::EQUIPMENT);
        assert((*self.tasks).len() == 0, errors::TASKS);
        assert(*self.facts & ~facts::HUB_REACHED == 0, errors::FACTS);
        assert(self.closes() || *self.belt == [0; 4], errors::BELT);
    }
}
