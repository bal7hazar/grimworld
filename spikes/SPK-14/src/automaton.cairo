//! The cellular automaton's rule on one limb, SPK-7's (`spikes/SPK-7/src/chunk.cairo`), shared by
//! both shapes: the six neighbour planes counted bit-sliced, then the biome's thresholds.

use hexx::board::bits::Bits;
use crate::types::Biome;

#[generate_trait]
pub impl AutomatonImpl of AutomatonTrait {
    /// The next walkable tiles of one limb, cut to `inside`.
    #[inline(always)]
    fn rule(
        grid: u128,
        a: u128,
        b: u128,
        c: u128,
        d: u128,
        e: u128,
        f: u128,
        inside: u128,
        biome: Biome,
    ) -> u128 {
        // [Compute] Two full adders, then the weight-1 half adder and the weight-2 full adder
        let (ab, x, _) = Bits::bitwise(a, b);
        let (xc, s1, _) = Bits::bitwise(x, c);
        let (de, y, _) = Bits::bitwise(d, e);
        let (yf, s2, _) = Bits::bitwise(y, f);
        let (c0, b0, _) = Bits::bitwise(s1, s2);
        let (both, either, _) = Bits::bitwise(ab + xc, de + yf);
        let (carry, b1, _) = Bits::bitwise(either, c0);
        let b2 = both + carry;
        // [Compute] Thresholds
        let next = match biome {
            // Born with 4+, survives with 3+
            Biome::Meadow => {
                let (pair, _, _) = Bits::bitwise(b1, b0);
                let (_, _, three) = Bits::bitwise(b2, pair);
                let (stay, _, _) = Bits::bitwise(grid, three);
                let (_, _, next) = Bits::bitwise(stay, b2);
                next
            },
            // Born and survives with 4+
            Biome::Forest => b2,
            // Born with 5+, survives with 4+
            Biome::Cave => {
                let (_, _, one) = Bits::bitwise(b1, b0);
                let (five, _, _) = Bits::bitwise(b2, one);
                let (stay, _, _) = Bits::bitwise(grid, b2);
                let (_, _, next) = Bits::bitwise(stay, five);
                next
            },
            Biome::Ruin => b2,
        };
        let (next, _, _) = Bits::bitwise(next, inside);
        next
    }
}
