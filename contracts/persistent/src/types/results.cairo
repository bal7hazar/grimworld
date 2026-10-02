//! The checks of `Results` at the hub (docs/architecture/ENG-01-interfaces.md §4.5, §6). `report`
//! settles what the persistent models hold today: experience, gold, balances, the belt's reserve
//! (credited back when a report closes the member's presence, on return and on defeat: D-141,
//! E-15), the placement and a hub reached. It refuses what has no model yet rather than drop it:
//! equipment drops (the pack's capacity, design/15), task increments (quiver's quests are not
//! embedded, E-14), the facts other than a hub reached (the "distinct" counters, the Rift board,
//! trials). ENG-06's report escalates each.

use grimworld_logic::interface::{Results, facts};
use grimworld_logic::types::{MAX_MEMBERS, Outcome};
use crate::models::balance::BalanceTrait;

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

    /// Whether it reports a hub reached (`facts::HUB_REACHED`): the hub is unlocked.
    #[inline(always)]
    fn reaches_hub(self: @Results) -> bool {
        *self.facts & facts::HUB_REACHED != 0
    }

    /// What it credits to the pack, as balance changes: the belt's reserve when it closes the
    /// presence (`belt`, the belt's items: one change per distinct item, D-141, E-15), then its
    /// balances, in their order.
    fn credit(self: @Results, belt: [u32; 4]) -> Array<(u32, u32)> {
        let mut credit = if self.closes() {
            BalanceTrait::merge(belt, *self.belt)
        } else {
            array![]
        };
        for balance in *self.balances {
            credit.append(*balance);
        }
        credit
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

#[cfg(test)]
mod tests {
    use grimworld_logic::interface::{Results, facts};
    use grimworld_logic::types::Outcome;
    use super::ResultsTrait;

    fn results(outcome: Outcome, facts: u32, belt: [u8; 4]) -> Results {
        Results {
            instance_id: 7,
            contributors: array![1].span(),
            experience: 0,
            gold: 0,
            balances: array![(9, 5), (4, 1)].span(),
            equipment: array![].span(),
            tasks: array![].span(),
            facts,
            location: 3,
            outcome,
            hub: 0,
            next: 0,
            belt,
        }
    }

    // The belt's reserve comes back only when the report closes the presence, merged by item,
    // before the balances, in their order.
    #[test]
    #[available_gas(l2_gas: 332052)] // ceil(1.05 × 316240 measured)
    fn test_credit() {
        let belt = [4, 8, 4, 0];
        let returned = results(Outcome::Returned, 0, [1, 2, 3, 0]);
        assert(returned.credit(belt) == array![(4, 4), (8, 2), (9, 5), (4, 1)], 'returned');
        let defeated = results(Outcome::Defeated, 0, [0, 2, 0, 0]);
        assert(defeated.credit(belt) == array![(8, 2), (9, 5), (4, 1)], 'defeated');
        let open = results(Outcome::Open, 0, [0; 4]);
        assert(open.credit(belt) == array![(9, 5), (4, 1)], 'open: balances only');
        let moved = results(Outcome::Moved, 0, [0; 4]);
        assert(moved.credit(belt) == array![(9, 5), (4, 1)], 'moved: balances only');
    }

    #[test]
    #[available_gas(l2_gas: 16652)] // ceil(1.05 × 15859 measured)
    fn test_reaches_hub() {
        assert(results(Outcome::Returned, facts::HUB_REACHED, [0; 4]).reaches_hub(), 'reached');
        assert(!results(Outcome::Returned, 0, [0; 4]).reaches_hub(), 'not reached');
        assert(!results(Outcome::Returned, 0x1, [0; 4]).reaches_hub(), 'another fact');
    }
}
