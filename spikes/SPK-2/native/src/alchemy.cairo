//! Discovery of a pair (design/07 *Discovery algorithm*), with and without the rarity signature
//! of D-52, in memory. The two differ only in how `mask` and the untried-pair counter are chosen.

use crate::board::{bitwise, pow};
use crate::models::{Book, Grimoire};
use crate::tables::POPCOUNT;

/// Signature of a pair of rarities (0 C, 1 U, 2 R), both orders: C+C, C+U, U+U, C+R, U+R, R+R.
const SIGNATURE: [u8; 9] = [0, 1, 3, 1, 2, 4, 3, 4, 5];

/// Region 1 book (design/07): 10 ingredients, 5 C + 3 U + 2 R, 12 recipes.
/// Rarities, 2 bits each: ingredients 0-4 C, 5-7 U, 8-9 R.
pub const REGION_1_RARITIES: u32 = 0xa5400; // 0b 10 10 01 01 01 00 00 00 00 00
/// Recipes per signature, 16 bits each: C+C {0,1,2}, C+U {3,4,5,6}, U+U {7}, C+R {8,9},
/// U+R {10}, R+R {11}.
pub const REGION_1_MASKS: u128 = 0x0800_0400_0300_0080_0078_0007;
pub const REGION_1_RECIPES: u16 = 0x0fff;
/// Untried pairs per signature, 8 bits each: 10, 15, 3, 10, 6, 1.
pub const REGION_1_REMAINING: u64 = 0x01_06_0a_03_0f_0a;
/// Every pair of the book.
pub const REGION_1_PAIRS: u64 = 45;

/// Number of set bits of a recipe mask: two lookups in a byte table.
#[inline(always)]
fn count(set: u16) -> u16 {
    let low = *POPCOUNT.span()[(set % 0x100).into()];
    let high = *POPCOUNT.span()[(set / 0x100).into()];
    (low + high).into()
}

/// Index of the `k`-th set bit (from the lowest), at most 16 iterations.
fn select(set: u16, k: u16) -> u8 {
    let mut set = set;
    let mut k = k;
    let mut index: u8 = 0;
    loop {
        if set % 2 == 1 {
            if k == 0 {
                break index;
            }
            k -= 1;
        }
        set /= 2;
        index += 1;
    }
}

/// Discover a pair never brewed by this adventurer.
/// # Arguments
/// * `book` - The book
/// * `grimoire` - The adventurer's grimoire of the book, updated
/// * `a`, `b` - The pair, `a < b`
/// * `word` - The random word (two independent draws are derived from it)
/// * `signed` - Whether the rarity signature applies (D-52)
/// # Returns
/// * The recipe found, `None` for a failed brew
pub fn discover(
    book: @Book, ref grimoire: Grimoire, a: u8, b: u8, word: felt252, signed: bool,
) -> Option<u8> {
    let (mask, left, unit) = if signed {
        // [Compute] Signature from two rarity lookups in the packed constant
        let rarities: u128 = (*book.rarities).into();
        let shift_a: u128 = pow(2 * a).try_into().unwrap();
        let shift_b: u128 = pow(2 * b).try_into().unwrap();
        let rarity_a = (rarities / shift_a) % 4;
        let rarity_b = (rarities / shift_b) % 4;
        let signature = *SIGNATURE.span()[(rarity_a * 3 + rarity_b).try_into().unwrap()];
        let shift: u128 = pow(16 * signature).try_into().unwrap();
        let mask: u16 = ((*book.masks / shift) % 0x10000).try_into().unwrap();
        let unit: u64 = pow(8 * signature).try_into().unwrap();
        let left: u64 = (grimoire.remaining / unit) % 0x100;
        (mask, left, unit)
    } else {
        (*book.recipes, grimoire.remaining % 0x100, 1)
    };
    // [Compute] Candidates and the success roll: count / left
    let (_, candidates, _) = bitwise(mask.into(), grimoire.known.into());
    let (candidates, _, _) = bitwise(candidates, mask.into());
    let candidates: u16 = candidates.try_into().unwrap();
    let n = count(candidates);
    let wide: u256 = word.into();
    let roll_1: u64 = (wide.low % left.into()).try_into().unwrap();
    grimoire.remaining -= unit;
    if roll_1 >= n.into() {
        return Option::None;
    }
    let roll_2: u16 = (wide.high % n.into()).try_into().unwrap();
    let recipe = select(candidates, roll_2);
    let bit: u16 = pow(recipe).try_into().unwrap();
    grimoire.known += bit;
    Option::Some(recipe)
}
