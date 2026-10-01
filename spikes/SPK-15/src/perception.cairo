//! Lever 4 alone (fix loop 1, finding 1): perception's selection on main's representation, every
//! goblin decoded. `World`'s goblin fields are private to `grimworld_logic`, so `Decoded` holds the
//! same three (`goblins`, `woken`, `awake`) and `awake_scan` is main's `TickTrait::awake` copied
//! verbatim from `contracts/logic/src/types/world.cairo` at `d4b5cdc` (its body, with main's own
//! `TickTrait::key` and `TickTrait::place`); `awake_single` is the same body with the one-pass
//! selection (`SelectionTrait::single`). `tests/bench_perception.cairo` checks that `awake_scan`
//! measures what main's `TickTrait::awake` measures and that all of them choose the same set.

use grimworld_logic::models::goblin::Goblin;
use grimworld_logic::types::world::{MAX_AWAKE, TickTrait, WorldTrait};
use crate::words::SelectionTrait;

/// Main's `World`, its goblins only.
#[derive(Drop, Debug)]
pub struct Decoded {
    pub goblins: Array<Goblin>,
    pub woken: Span<u32>,
    pub awake: Array<Goblin>,
}

#[generate_trait]
pub impl DecodedImpl of DecodedTrait {
    /// The goblins of `goblins` (ascending entity id), the set formed from their flags (main's
    /// `WorldTrait::split`).
    fn new(goblins: Array<Goblin>) -> Decoded {
        let (woken, awake) = WorldTrait::split(goblins.span());
        Decoded { goblins, woken, awake }
    }

    /// Goblin `index` as it is now (main's `WorldTrait::goblin`).
    fn goblin(self: @Decoded, index: u32) -> Goblin {
        let mut k = 0;
        let mut found: Option<u32> = None;
        for i in *self.woken {
            if *i == index {
                found = Some(k);
            }
            k += 1;
        }
        match found {
            Some(k) => *self.awake[k],
            None => *self.goblins[index],
        }
    }

    /// Main's `TickTrait::awake`, verbatim.
    fn awake_scan(ref self: Decoded, distances: Span<u16>) {
        let count = self.goblins.len();
        assert(distances.len() == count, 'tick: one distance a goblin');
        let all = self.goblins.span();
        let woken = self.woken;
        let values = self.awake.span();
        // Each candidate's key, `distance × 2^16 + entity`, is unique: select the 8 smallest.
        let mut keys: Array<u32> = array![];
        let mut from = 0;
        let mut k = 0;
        for index in woken {
            while from < *index {
                keys.append(TickTrait::key(all[from], *distances[from]));
                from += 1;
            }
            keys.append(TickTrait::key(values[k], *distances[from]));
            from += 1;
            k += 1;
        }
        while from < count {
            keys.append(TickTrait::key(all[from], *distances[from]));
            from += 1;
        }
        let keys = keys.span();
        let mut last: u32 = 0;
        let mut found = 0;
        while found < MAX_AWAKE {
            let mut least: u32 = 0xFFFFFFFF;
            for key in keys {
                if (found == 0 || *key > last) && *key < least {
                    least = *key;
                }
            }
            if least == 0xFFFFFFFF {
                break;
            }
            last = least;
            found += 1;
        }
        self.place(keys, found, last);
    }

    /// The same, the 8 smallest keys found in one pass.
    fn awake_single(ref self: Decoded, distances: Span<u16>) {
        let count = self.goblins.len();
        assert(distances.len() == count, 'tick: one distance a goblin');
        let all = self.goblins.span();
        let woken = self.woken;
        let values = self.awake.span();
        let mut keys: Array<u32> = array![];
        let mut from = 0;
        let mut k = 0;
        for index in woken {
            while from < *index {
                keys.append(TickTrait::key(all[from], *distances[from]));
                from += 1;
            }
            keys.append(TickTrait::key(values[k], *distances[from]));
            from += 1;
            k += 1;
        }
        while from < count {
            keys.append(TickTrait::key(all[from], *distances[from]));
            from += 1;
        }
        let keys = keys.span();
        let (found, last) = SelectionTrait::single(keys);
        self.place(keys, found, last);
    }

    /// Main's pass that writes the flags and forms the set apart again, verbatim.
    #[inline(always)]
    fn place(ref self: Decoded, keys: Span<u32>, found: u32, last: u32) {
        let count = self.goblins.len();
        let all = self.goblins.span();
        let woken = self.woken;
        let values = self.awake.span();
        let any = found > 0;
        let mut goblins = array![];
        let mut now: Array<u32> = array![];
        let mut awake = array![];
        let mut from = 0;
        let mut k = 0;
        for index in woken {
            while from < *index {
                let flag = any && *keys[from] <= last;
                TickTrait::place(ref goblins, ref now, ref awake, *all[from], from, flag);
                from += 1;
            }
            let flag = any && *keys[from] <= last;
            TickTrait::place(ref goblins, ref now, ref awake, *values[k], from, flag);
            from += 1;
            k += 1;
        }
        while from < count {
            let flag = any && *keys[from] <= last;
            TickTrait::place(ref goblins, ref now, ref awake, *all[from], from, flag);
            from += 1;
        }
        self.goblins = goblins;
        self.woken = now.span();
        self.awake = awake;
    }
}
