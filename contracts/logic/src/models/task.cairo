//! The tasks an instance reports (D-131): `TaskEntry`, and `TaskPage`, four of them in one stored
//! word (bit offsets in docs/architecture/ENG-01-interfaces.md).

use crate::helpers::packing::{P32, P40, P56, P8, PackingTrait};

/// One task an instance reports (D-131): the quiver task id and what counts toward it, which the
/// instance can check without reading the persistent domain.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct TaskEntry {
    pub task: u32,
    /// `criteria` of docs/architecture/ENG-01-interfaces.md: 1 kill a caste, 2 reach a landmark,
    /// 3 clear a dungeon, 4 reveal a whole zone, 5 loot remains, 6 mine, 7 activate objects.
    pub kind: u8,
    /// The registry id the kind counts (a caste, a landmark, a location).
    pub param: u16,
}

/// Four tasks per stored page: at bits 0 and 56 (low limb), 128 and 184 (high limb).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct TaskPage {
    pub entries: [TaskEntry; 4],
}

/// One entry's 56 bits: the task 0–31 · its kind 32–39 · its param 40–55.
#[generate_trait]
impl TaskEntryImpl of TaskEntryTrait {
    fn pack(t: TaskEntry) -> u128 {
        t.task.into() + t.kind.into() * P32 + t.param.into() * P40
    }

    fn unpack(bits: u128) -> TaskEntry {
        let (rest, task) = DivRem::div_rem(bits, P32.try_into().unwrap());
        let (param, kind) = DivRem::div_rem(rest, P8.try_into().unwrap());
        TaskEntry {
            task: task.try_into().unwrap(),
            kind: kind.try_into().unwrap(),
            param: param.try_into().unwrap(),
        }
    }
}

#[generate_trait]
pub impl TaskPageImpl of TaskPageTrait {
    fn pack(p: TaskPage) -> felt252 {
        let [a, b, c, d] = p.entries;
        PackingTrait::join(
            TaskEntryTrait::pack(a) + TaskEntryTrait::pack(b) * P56,
            TaskEntryTrait::pack(c) + TaskEntryTrait::pack(d) * P56,
        )
    }

    fn unpack(word: felt252) -> TaskPage {
        let (low, high) = PackingTrait::split(word);
        let s56: NonZero<u128> = P56.try_into().unwrap();
        let (b, a) = DivRem::div_rem(low, s56);
        let (d, c) = DivRem::div_rem(high, s56);
        TaskPage {
            entries: [
                TaskEntryTrait::unpack(a), TaskEntryTrait::unpack(b), TaskEntryTrait::unpack(c),
                TaskEntryTrait::unpack(d),
            ],
        }
    }
}

pub impl TaskPageStorePacking of starknet::storage_access::StorePacking<TaskPage, felt252> {
    fn pack(value: TaskPage) -> felt252 {
        TaskPageTrait::pack(value)
    }
    fn unpack(value: felt252) -> TaskPage {
        TaskPageTrait::unpack(value)
    }
}

#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use super::{TaskEntry, TaskPage, TaskPageTrait};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    #[test]
    #[available_gas(l2_gas: 140763)] // ceil(1.05 × 134060 measured)
    fn test_task_page_layout() {
        let full = TaskEntry { task: 0xFFFFFFFF, kind: 0xFF, param: 0xFFFF };
        let page = TaskPage {
            entries: [full, TaskEntry { task: 1, kind: 2, param: 3 }, full, full],
        };
        assert(TaskPageTrait::unpack(TaskPageTrait::pack(page)) == page, 'round trip');
        let second = TaskPage {
            entries: [
                Default::default(), TaskEntry { task: 1, kind: 0, param: 0 }, Default::default(),
                TaskEntry { task: 0, kind: 1, param: 0 },
            ],
        };
        // Entry 1 at bit 56; entry 3 at bit 184, its kind at bit 216.
        let expected = 0x100000000000000 + 0x100000000 * 0x100000000000000 * TWO_128 + LIVE;
        assert(TaskPageTrait::pack(second) == expected, 'offsets');
    }
}
