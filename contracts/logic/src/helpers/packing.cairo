//! Packing of records into one felt (docs/CAIRO.md §4; docs/architecture/ENG-01-interfaces.md,
//! *Packing*). Every layout of the game follows three rules:
//! - a field never straddles bit 128, so that a record is read as two `u128` limbs;
//! - bit 250 (`LIVE`) is set in every stored record, so that a reused slot never holds 0: the
//!   local node prices a key written again after it held 0 as a new slot, about 14 times an
//!   overwrite (ENG-01, *Reuse, measured*);
//! - bits 251 and up do not exist (a felt is below 2^251 + 17·2^192 + 1).
//!
//! `u256` is used only to split a felt into its two limbs (written reason: the `felt252 → u256`
//! conversion, `u128s_from_felt252`, is the only range proof of a full felt on Cairo 2.19;
//! `hexx`'s bitmaps split the same way, D-173).
//!
//! What a split costs (CBT-02b, lever (b); snforge, per word): the conversion about 1,700 L2 gas;
//! removing `LIVE` by a comparison and a subtraction 1,340 more (`split` before CBT-02b), by one
//! overflowing subtraction 1,070 (`split`), by a field subtraction before the conversion 100
//! (`limbs`, for a word known to carry `LIVE`). A field read by two divisions (`field`) costs about
//! 2,600; the decoders of hot words read their fields in one pass of divisions, one a field.

use core::num::traits::OverflowingSub;

/// Bit 250, set in every stored record: a stored slot is never 0.
pub const LIVE: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
/// `LIVE` as seen in the high limb (bit 122 of it).
pub const LIVE_HIGH: u128 = 0x4000000000000000000000000000000;
/// 2^128.
pub const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;

#[generate_trait]
pub impl PackingImpl of PackingTrait {
    /// The two limbs of a word, `LIVE` removed from the high one if it is set: any word, a slot
    /// never written (0) included. One overflowing subtraction decides and removes `LIVE`.
    #[inline(always)]
    fn split(word: felt252) -> (u128, u128) {
        let wide: u256 = word.into();
        let (high, borrow) = OverflowingSub::overflowing_sub(wide.high, LIVE_HIGH);
        if borrow {
            (wide.low, wide.high)
        } else {
            (wide.low, high)
        }
    }

    /// The two limbs of a stored record, which carries `LIVE` (rule 2 above: every record the game
    /// writes, and every registry part), `LIVE` removed as a field subtraction before the
    /// conversion.
    /// A word without `LIVE` (a slot never written) must go through `split`: here it would decode
    /// as another value.
    #[inline(always)]
    fn limbs(word: felt252) -> (u128, u128) {
        let wide: u256 = (word - LIVE).into();
        (wide.low, wide.high)
    }

    /// A stored record from its two limbs, `LIVE` set. `high` must be below 2^122: a field that
    /// overflows into `LIVE` or beyond is refused, never written.
    #[inline(always)]
    fn join(low: u128, high: u128) -> felt252 {
        assert(high < LIVE_HIGH, 'packing: high limb overflow');
        low.into() + high.into() * TWO_POW_128 + LIVE
    }
}

#[generate_trait]
pub impl LimbImpl of LimbTrait {
    /// The low field of `rest`, of width `2^width = size`, which it removes: a limb read field
    /// after field from its low bits costs one division a field (`field` costs two).
    #[inline(always)]
    fn peel(ref rest: u128, size: NonZero<u128>) -> u128 {
        let (above, value) = DivRem::div_rem(rest, size);
        rest = above;
        value
    }

    /// The field of `limb` at bit `2^offset = shift`, of width `2^width = size`.
    #[inline(always)]
    fn field(limb: u128, shift: u128, size: u128) -> u128 {
        let (above, _) = DivRem::div_rem(limb, shift.try_into().unwrap());
        let (_, value) = DivRem::div_rem(above, size.try_into().unwrap());
        value
    }

    /// The byte of `limb` at bit `2^offset = shift`.
    #[inline(always)]
    fn byte_at(limb: u128, shift: u128) -> u8 {
        Self::field(limb, shift, 0x100).try_into().unwrap()
    }

    /// The `u16` of `limb` at bit `2^offset = shift`.
    #[inline(always)]
    fn u16_at(limb: u128, shift: u128) -> u16 {
        Self::field(limb, shift, 0x10000).try_into().unwrap()
    }

    /// The `u32` of `limb` at bit `2^offset = shift`.
    #[inline(always)]
    fn u32_at(limb: u128, shift: u128) -> u32 {
        Self::field(limb, shift, 0x100000000).try_into().unwrap()
    }

    /// The low field of `limb`, of width `2^width = size`.
    #[inline(always)]
    fn low_field(limb: u128, size: NonZero<u128>) -> u128 {
        let (_, value) = DivRem::div_rem(limb, size);
        value
    }
}

#[generate_trait]
pub impl PackingAssert of PackingAssertTrait {
    /// Refuses a value wider than its field (`size = 2^width`): a packer checks every field
    /// narrower than its Cairo type, so that it can never corrupt its neighbour (ENG-01 fix loop 1,
    /// F-9).
    #[inline(always)]
    fn assert_fits(value: u128, size: u128, message: felt252) {
        assert(value < size, message);
    }
}

// The same powers as divisors, for `LimbTrait::peel` (a table).
pub const N2: NonZero<u128> = 0x2;
pub const N4: NonZero<u128> = 0x10;
pub const N6: NonZero<u128> = 0x40;
pub const N7: NonZero<u128> = 0x80;
pub const N8: NonZero<u128> = 0x100;
pub const N16: NonZero<u128> = 0x10000;
pub const N24: NonZero<u128> = 0x1000000;
pub const N28: NonZero<u128> = 0x10000000;
pub const N32: NonZero<u128> = 0x100000000;
pub const N56: NonZero<u128> = 0x100000000000000;

// Powers of two used by the layouts (a table, docs/CAIRO.md §3).
pub const P4: u128 = 0x10;
pub const P5: u128 = 0x20;
pub const P8: u128 = 0x100;
pub const P12: u128 = 0x1000;
pub const P16: u128 = 0x10000;
pub const P20: u128 = 0x100000;
pub const P24: u128 = 0x1000000;
pub const P25: u128 = 0x2000000;
pub const P28: u128 = 0x10000000;
pub const P32: u128 = 0x100000000;
pub const P36: u128 = 0x1000000000;
pub const P40: u128 = 0x10000000000;
pub const P44: u128 = 0x100000000000;
pub const P48: u128 = 0x1000000000000;
pub const P52: u128 = 0x10000000000000;
pub const P56: u128 = 0x100000000000000;
pub const P60: u128 = 0x1000000000000000;
pub const P64: u128 = 0x10000000000000000;
pub const P72: u128 = 0x1000000000000000000;
pub const P80: u128 = 0x100000000000000000000;
pub const P84: u128 = 0x1000000000000000000000;
pub const P88: u128 = 0x10000000000000000000000;
pub const P96: u128 = 0x1000000000000000000000000;
pub const P100: u128 = 0x10000000000000000000000000;
pub const P104: u128 = 0x100000000000000000000000000;
pub const P108: u128 = 0x1000000000000000000000000000;
pub const P112: u128 = 0x10000000000000000000000000000;
pub const P120: u128 = 0x1000000000000000000000000000000;

/// Seven `u32` lanes in one felt: lanes 0 to 3 in the low limb, 4 to 6 in the high one (bits 128
/// to 223). Used for every list of `u32` ids and every page of balances.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Lanes32 {
    pub lanes: [u32; 7],
}

#[generate_trait]
pub impl Lanes32Impl of Lanes32Trait {
    fn pack(value: Lanes32) -> felt252 {
        let [a, b, c, d, e, f, g] = value.lanes;
        let low: u128 = a.into() + b.into() * P32 + c.into() * P64 + d.into() * P96;
        let high: u128 = e.into() + f.into() * P32 + g.into() * P64;
        PackingTrait::join(low, high)
    }

    fn unpack(word: felt252) -> Lanes32 {
        let (low, high) = PackingTrait::split(word);
        let s32: NonZero<u128> = P32.try_into().unwrap();
        let (low, a) = DivRem::div_rem(low, s32);
        let (low, b) = DivRem::div_rem(low, s32);
        let (d, c) = DivRem::div_rem(low, s32);
        let (high, e) = DivRem::div_rem(high, s32);
        let (g, f) = DivRem::div_rem(high, s32);
        Lanes32 {
            lanes: [
                a.try_into().unwrap(), b.try_into().unwrap(), c.try_into().unwrap(),
                d.try_into().unwrap(), e.try_into().unwrap(), f.try_into().unwrap(),
                g.try_into().unwrap(),
            ],
        }
    }
}

pub impl Lanes32StorePacking of starknet::storage_access::StorePacking<Lanes32, felt252> {
    fn pack(value: Lanes32) -> felt252 {
        Lanes32Trait::pack(value)
    }
    fn unpack(value: felt252) -> Lanes32 {
        Lanes32Trait::unpack(value)
    }
}

/// Fifteen `u16` lanes in one felt: lanes 0 to 7 in the low limb, 8 to 14 in the high one (bits
/// 128 to 239). Used for lists of entity ids and of `u16` content ids.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Lanes16 {
    pub lanes: [u16; 15],
}

#[generate_trait]
pub impl Lanes16Impl of Lanes16Trait {
    fn pack(value: Lanes16) -> felt252 {
        let mut low: u128 = 0;
        let mut high: u128 = 0;
        let mut factor: u128 = 1;
        let mut i: u32 = 0;
        for lane in value.lanes.span() {
            if i == 8 {
                factor = 1;
            }
            if i < 8 {
                low += (*lane).into() * factor;
            } else {
                high += (*lane).into() * factor;
            }
            if i != 7 && i != 14 {
                factor *= P16;
            }
            i += 1;
        }
        PackingTrait::join(low, high)
    }

    fn unpack(word: felt252) -> Lanes16 {
        let (low, high) = PackingTrait::split(word);
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let mut out: Array<u16> = array![];
        let mut rest = low;
        for _ in 0..8_u8 {
            let (next, lane) = DivRem::div_rem(rest, s16);
            out.append(lane.try_into().unwrap());
            rest = next;
        }
        rest = high;
        for _ in 0..7_u8 {
            let (next, lane) = DivRem::div_rem(rest, s16);
            out.append(lane.try_into().unwrap());
            rest = next;
        }
        let lanes: [u16; 15] = [
            *out[0], *out[1], *out[2], *out[3], *out[4], *out[5], *out[6], *out[7], *out[8],
            *out[9], *out[10], *out[11], *out[12], *out[13], *out[14],
        ];
        Lanes16 { lanes }
    }
}

pub impl Lanes16StorePacking of starknet::storage_access::StorePacking<Lanes16, felt252> {
    fn pack(value: Lanes16) -> felt252 {
        Lanes16Trait::pack(value)
    }
    fn unpack(value: felt252) -> Lanes16 {
        Lanes16Trait::unpack(value)
    }
}

/// A counter kept with `LIVE`, so that it is never 0 in storage: a counter that returns to 0 (the
/// open lots) and rises again would otherwise pay a new slot each time (ENG-01, *Reuse, measured*).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Counter {
    pub value: u64,
}

pub impl CounterStorePacking of starknet::storage_access::StorePacking<Counter, felt252> {
    fn pack(value: Counter) -> felt252 {
        PackingTrait::join(value.value.into(), 0)
    }
    fn unpack(value: felt252) -> Counter {
        let (low, _) = PackingTrait::split(value);
        Counter { value: low.try_into().unwrap() }
    }
}

/// A bitmap of 250 bits (bits 0 to 249) in one felt, `LIVE` at bit 250: the revealed set of an
/// instance (bit `15 cy + cx`), known skills, "distinct" counters of titles (T-2).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Bitmap {
    pub bits: felt252,
}

pub impl BitmapStorePacking of starknet::storage_access::StorePacking<Bitmap, felt252> {
    fn pack(value: Bitmap) -> felt252 {
        let wide: u256 = value.bits.into();
        assert(wide.high < LIVE_HIGH, 'packing: bitmap above bit 249');
        value.bits + LIVE
    }
    fn unpack(value: felt252) -> Bitmap {
        let (low, high) = PackingTrait::split(value);
        Bitmap { bits: low.into() + high.into() * TWO_POW_128 }
    }
}

/// The vector table for the TypeScript mirror (VEC-01) is printed by `tests::test_vectors` and kept
/// in `contracts/logic/vectors/packing.jsonl` (`vectors/README.md`).
#[cfg(test)]
mod tests {
    use core::poseidon::poseidon_hash_span;
    use starknet::storage_access::StorePacking;
    use super::{
        Bitmap, BitmapStorePacking, Counter, CounterStorePacking, LIVE, LIVE_HIGH, Lanes16,
        Lanes16StorePacking, Lanes16Trait, Lanes32, Lanes32StorePacking, Lanes32Trait, LimbTrait,
        N16, N2, N24, N28, N32, N4, N56, N6, N7, N8, P108, P112, P12, P120, P16, P32, P4, P40, P56,
        P60, P64, P72, P8, P96, PackingAssert, PackingTrait, TWO_POW_128,
    };

    fn hex(felts: Span<felt252>) -> ByteArray {
        let mut out: ByteArray = "[";
        let mut first = true;
        for felt in felts {
            if !first {
                out.append(@",");
            }
            first = false;
            let wide: u256 = (*felt).into();
            out.append(@format!("\"0x{:x}\"", wide));
        }
        out.append(@"]");
        out
    }

    /// Prints one vector and adds it to the digest.
    fn emit(
        ref digest: Array<felt252>,
        ref id: u32,
        name: ByteArray,
        case: Span<felt252>,
        ok: Span<felt252>,
    ) {
        println!("{{\"id\":{},\"fn\":\"{}\",\"case\":{},\"ok\":{}}}", id, name, hex(case), hex(ok));
        digest.append(poseidon_hash_span(case));
        digest.append(poseidon_hash_span(ok));
        id += 1;
    }

    const MAX: felt252 = -1;
    const U128_MAX: u128 = 0xffffffffffffffffffffffffffffffff;
    const LIVE_LOW_MAX: felt252 = 0x3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// Cases with a refusal: `[0, result…]` accepted, `[1]` refused (the `Option` convention of
    /// the window's `arc`). A panic cannot be caught in a test, so a refusal is the guard evaluated
    /// here; the panics themselves are asserted by this module's `should_panic` tests.
    fn accepted(result: Span<felt252>) -> Array<felt252> {
        let mut out: Array<felt252> = array![0];
        out.append_span(result);
        out
    }

    fn lanes32_with(j: u32, v: u32) -> Lanes32 {
        Lanes32 {
            lanes: [
                if j == 0 {
                    v
                } else {
                    0
                }, if j == 1 {
                    v
                } else {
                    0
                }, if j == 2 {
                    v
                } else {
                    0
                },
                if j == 3 {
                    v
                } else {
                    0
                }, if j == 4 {
                    v
                } else {
                    0
                }, if j == 5 {
                    v
                } else {
                    0
                },
                if j == 6 {
                    v
                } else {
                    0
                },
            ],
        }
    }

    fn at16(j: u32, k: u32, v: u16) -> u16 {
        if j == k {
            v
        } else {
            0
        }
    }

    fn lanes16_with(j: u32, v: u16) -> Lanes16 {
        Lanes16 {
            lanes: [
                at16(j, 0, v), at16(j, 1, v), at16(j, 2, v), at16(j, 3, v), at16(j, 4, v),
                at16(j, 5, v), at16(j, 6, v), at16(j, 7, v), at16(j, 8, v), at16(j, 9, v),
                at16(j, 10, v), at16(j, 11, v), at16(j, 12, v), at16(j, 13, v), at16(j, 14, v),
            ],
        }
    }

    fn serialize<T, +Serde<T>, +Drop<T>>(value: T) -> Array<felt252> {
        let mut out: Array<felt252> = array![];
        value.serialize(ref out);
        out
    }

    // The refusal rows of `fits` are its guard evaluated by `test_vectors`: this asserts the panic
    // at the boundary, `value == size`.
    #[test]
    #[should_panic(expected: 'fits')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_fits_refuses_size() {
        PackingAssert::assert_fits(2, 2, 'fits');
    }

    // The vector table, one JSON line per case (`{"id", "fn", "case", "ok"}`), and a digest of
    // every case and outcome: a change to a layout or to the cases fails here until
    // `contracts/logic/vectors/packing.jsonl` is regenerated.
    #[test]
    #[available_gas(l2_gas: 653389147)] // ceil(1.05 × 622275378 measured)
    fn test_vectors() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = 0;
        let limb_values: [u128; 7] = [
            0, 1, U128_MAX, 0x0123456789abcdef0123456789abcdef, 0x10000000000000000,
            0xffffffffffffffff, LIVE_HIGH,
        ];

        // `split`: any word, `LIVE` removed from the high limb when it is set.
        let words: [felt252; 14] = [
            0, 1, LIVE, LIVE + 1, TWO_POW_128 + 1, TWO_POW_128 - 1, TWO_POW_128, LIVE + TWO_POW_128,
            LIVE + LIVE_LOW_MAX, LIVE_LOW_MAX, LIVE + 0x0123456789abcdef0123456789abcdef, 2 * LIVE,
            MAX, MAX - LIVE,
        ];
        for word in words.span() {
            let (low, high) = PackingTrait::split(*word);
            emit(ref digest, ref id, "split", [*word].span(), [low.into(), high.into()].span());
        }
        // `limbs`: a word that carries `LIVE` (0 is the wrapped case, outside the contract).
        let stored: [felt252; 8] = [
            LIVE, LIVE + 1, LIVE + U128_MAX.into(), LIVE + TWO_POW_128, LIVE + LIVE_LOW_MAX,
            LIVE + 0x0123456789abcdef0123456789abcdef, MAX - 1, 0,
        ];
        for word in stored.span() {
            let (low, high) = PackingTrait::limbs(*word);
            emit(ref digest, ref id, "limbs", [*word].span(), [low.into(), high.into()].span());
        }
        // `join`: the boundary of the high limb is 2^122 (`LIVE_HIGH`).
        let highs: [u128; 8] = [
            0, 1, 0x123456789abcdef, LIVE_HIGH - 1, LIVE_HIGH, LIVE_HIGH + 1,
            0x8000000000000000000000000000000, U128_MAX,
        ];
        for low in limb_values.span() {
            for high in highs.span() {
                let case = [(*low).into(), (*high).into()];
                if *high < LIVE_HIGH {
                    let ok = accepted([PackingTrait::join(*low, *high)].span());
                    emit(ref digest, ref id, "join", case.span(), ok.span());
                } else {
                    emit(ref digest, ref id, "join", case.span(), [1].span());
                }
            }
        }
        // `LimbTrait::peel`: the low field of each width, and what remains.
        let sizes: [NonZero<u128>; 10] = [N2, N4, N6, N7, N8, N16, N24, N28, N32, N56];
        for size in sizes.span() {
            let size_value: u128 = (*size).into();
            for limb in limb_values.span() {
                let mut rest = *limb;
                let value = LimbTrait::peel(ref rest, *size);
                emit(
                    ref digest,
                    ref id,
                    "peel",
                    [(*limb).into(), size_value.into()].span(),
                    [value.into(), rest.into()].span(),
                );
            }
        }
        // `fits`: a value below its field's size is accepted, from the size up it is refused.
        let fit_sizes: [u128; 5] = [2, 0x10, 0x100, 0x10000, 0x100000000];
        for size in fit_sizes.span() {
            for value in [0, 1, *size - 1, *size, *size + 1, U128_MAX].span() {
                let case = [(*value).into(), (*size).into()];
                if *value < *size {
                    PackingAssert::assert_fits(*value, *size, 'fits');
                    emit(ref digest, ref id, "fits", case.span(), accepted([].span()).span());
                } else {
                    emit(ref digest, ref id, "fits", case.span(), [1].span());
                }
            }
        }
        // `LimbTrait::{field, byte_at, u16_at, u32_at, low_field}`.
        let shifts: [(u128, u128); 8] = [
            (1, 2), (1, 0x100), (P8, 0x100), (P16, P16), (P64, P32), (P96, P32), (P120, 0x100),
            (P4, P12),
        ];
        for limb in limb_values.span() {
            for pair in shifts.span() {
                let (shift, size) = *pair;
                let ok = LimbTrait::field(*limb, shift, size);
                emit(
                    ref digest,
                    ref id,
                    "field",
                    [(*limb).into(), shift.into(), size.into()].span(),
                    [ok.into()].span(),
                );
            }
            for shift in [1, P8, P56, P120].span() {
                let ok = LimbTrait::byte_at(*limb, *shift);
                emit(
                    ref digest,
                    ref id,
                    "byte_at",
                    [(*limb).into(), (*shift).into()].span(),
                    [ok.into()].span(),
                );
            }
            for shift in [1, P16, P60, P112].span() {
                let ok = LimbTrait::u16_at(*limb, *shift);
                emit(
                    ref digest,
                    ref id,
                    "u16_at",
                    [(*limb).into(), (*shift).into()].span(),
                    [ok.into()].span(),
                );
            }
            for shift in [1, P32, P64, P96].span() {
                let ok = LimbTrait::u32_at(*limb, *shift);
                emit(
                    ref digest,
                    ref id,
                    "u32_at",
                    [(*limb).into(), (*shift).into()].span(),
                    [ok.into()].span(),
                );
            }
            for size in [2, P12, P40, P72, P108].span() {
                let ok = LimbTrait::low_field(*limb, (*size).try_into().unwrap());
                emit(
                    ref digest,
                    ref id,
                    "low_field",
                    [(*limb).into(), (*size).into()].span(),
                    [ok.into()].span(),
                );
            }
        }

        // `Lanes32`: pack (the seven lanes to a word), unpack (a word to the seven lanes).
        let mut lanes: Array<Lanes32> = array![
            Lanes32 { lanes: [0, 0, 0, 0, 0, 0, 0] }, Lanes32 { lanes: [1, 2, 3, 4, 5, 6, 7] },
            Lanes32 { lanes: [0xffffffff; 7] }, Lanes32 { lanes: [1; 7] },
        ];
        for j in 0..7_u32 {
            for v in [1, 0x12345678, 0xffffffff].span() {
                lanes.append(lanes32_with(j, *v));
            }
        }
        for value in lanes.span() {
            let word = Lanes32Trait::pack(*value);
            emit(ref digest, ref id, "pack_lanes32", serialize(*value).span(), [word].span());
            emit(
                ref digest,
                ref id,
                "unpack_lanes32",
                [word].span(),
                serialize(Lanes32Trait::unpack(word)).span(),
            );
        }
        // A word without `LIVE` (a slot never written) decodes as zero lanes.
        for word in [0, 1, 0x1ffffffff].span() {
            emit(
                ref digest,
                ref id,
                "unpack_lanes32",
                [*word].span(),
                serialize(Lanes32Trait::unpack(*word)).span(),
            );
        }
        // The `StorePacking` impl is the same two functions.
        let stored = Lanes32StorePacking::pack(Lanes32 { lanes: [9, 8, 7, 6, 5, 4, 3] });
        emit(ref digest, ref id, "pack_lanes32", [9, 8, 7, 6, 5, 4, 3].span(), [stored].span());

        // `Lanes16`.
        let mut lanes: Array<Lanes16> = array![
            Lanes16 { lanes: [0; 15] },
            Lanes16 { lanes: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15] },
            Lanes16 { lanes: [0xffff; 15] }, Lanes16 { lanes: [1; 15] },
        ];
        for j in 0..15_u32 {
            for v in [1, 0xffff].span() {
                lanes.append(lanes16_with(j, *v));
            }
        }
        for value in lanes.span() {
            let word = Lanes16Trait::pack(*value);
            emit(ref digest, ref id, "pack_lanes16", serialize(*value).span(), [word].span());
            emit(
                ref digest,
                ref id,
                "unpack_lanes16",
                [word].span(),
                serialize(Lanes16Trait::unpack(word)).span(),
            );
        }
        for word in [0, 1, 0x1ffff].span() {
            emit(
                ref digest,
                ref id,
                "unpack_lanes16",
                [*word].span(),
                serialize(Lanes16Trait::unpack(*word)).span(),
            );
        }
        let stored = Lanes16StorePacking::pack(Lanes16 { lanes: [3; 15] });
        emit(ref digest, ref id, "pack_lanes16", [3; 15].span(), [stored].span());

        // `Counter`: never 0 in storage; unpack reads the low limb only.
        for value in [
            0, 1, 2, 255, 0xffffffff, 0x100000000, 0xfffffffffffffffe, 0xffffffffffffffff_u64,
        ]
            .span() {
            let word = CounterStorePacking::pack(Counter { value: *value });
            emit(ref digest, ref id, "pack_counter", [(*value).into()].span(), [word].span());
            emit(
                ref digest,
                ref id,
                "unpack_counter",
                [word].span(),
                serialize(CounterStorePacking::unpack(word)).span(),
            );
        }
        emit(
            ref digest,
            ref id,
            "unpack_counter",
            [0].span(),
            serialize(CounterStorePacking::unpack(0)).span(),
        );

        // `Bitmap`: 250 bits; bit 250 and above are refused.
        let bits: [felt252; 12] = [
            0, 1, 2, 0xffffffffffffffff, U128_MAX.into(), TWO_POW_128, TWO_POW_128 + 1,
            0x0123456789abcdef0123456789abcdef0123456789abcdef, LIVE_LOW_MAX - 1, LIVE_LOW_MAX,
            LIVE, LIVE + 1,
        ];
        for value in bits.span() {
            let wide: u256 = (*value).into();
            if wide.high < LIVE_HIGH {
                let word = BitmapStorePacking::pack(Bitmap { bits: *value });
                emit(
                    ref digest,
                    ref id,
                    "pack_bitmap",
                    [*value].span(),
                    accepted([word].span()).span(),
                );
                emit(
                    ref digest,
                    ref id,
                    "unpack_bitmap",
                    [word].span(),
                    serialize(BitmapStorePacking::unpack(word)).span(),
                );
            } else {
                emit(ref digest, ref id, "pack_bitmap", [*value].span(), [1].span());
            }
        }
        emit(ref digest, ref id, "pack_bitmap", [MAX].span(), [1].span());
        emit(
            ref digest,
            ref id,
            "unpack_bitmap",
            [0].span(),
            serialize(BitmapStorePacking::unpack(0)).span(),
        );
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST, 'vectors moved: regenerate');
    }

    const DIGEST: felt252 =
        2846947247712031828191250240930051473826381931961835652957099604656858941268;

    #[test]
    #[available_gas(l2_gas: 108045)] // ceil(1.05 × 102900 measured)
    fn test_lanes32() {
        let lanes = Lanes32 { lanes: [1, 2, 3, 0xFFFFFFFF, 5, 6, 0xFFFFFFFF] };
        let word = Lanes32Trait::pack(lanes);
        assert(Lanes32Trait::unpack(word) == lanes, 'round trip');
        let one = Lanes32Trait::pack(Lanes32 { lanes: [0, 0, 0, 0, 1, 0, 0] });
        assert(one == TWO_POW_128 + LIVE, 'lane 4 at bit 128');
        assert(Lanes32Trait::pack(Lanes32 { lanes: [0; 7] }) == LIVE, 'empty is LIVE, not 0');
        assert(Lanes32Trait::unpack(0) == Lanes32 { lanes: [0; 7] }, 'unwritten is empty');
    }

    #[test]
    #[available_gas(l2_gas: 443289)] // ceil(1.05 × 422180 measured)
    fn test_lanes16() {
        let lanes = Lanes16 { lanes: [1, 2, 3, 4, 5, 6, 7, 0xFFFF, 9, 10, 11, 12, 13, 14, 0xFFFF] };
        assert(Lanes16Trait::unpack(Lanes16Trait::pack(lanes)) == lanes, 'round trip');
        let mut one = [0_u16; 15];
        let [a, b, c, d, e, f, g, h, _, j, k, l, m, n, o] = one;
        one = [a, b, c, d, e, f, g, h, 1, j, k, l, m, n, o];
        assert(
            Lanes16Trait::pack(Lanes16 { lanes: one }) == TWO_POW_128 + LIVE, 'lane 8 at bit 128',
        );
    }

    #[test]
    #[available_gas(l2_gas: 12999)] // ceil(1.05 × 12380 measured)
    fn test_bitmap() {
        let top: felt252 =
            0x200000000000000000000000000000000000000000000000000000000000000; // 2^249
        let bitmap = Bitmap { bits: top + 1 };
        let word = StorePacking::<Bitmap, felt252>::pack(bitmap);
        assert(word == top + 1 + LIVE, 'LIVE above bit 249');
        assert(StorePacking::<Bitmap, felt252>::unpack(word) == bitmap, 'round trip');
    }

    // Fix loop 1: a counter is never 0 in storage (F-4); a high limb that would reach LIVE, or a
    // bitmap above bit 249, is refused (F-9).
    #[test]
    #[available_gas(l2_gas: 10679)] // ceil(1.05 × 10170 measured)
    fn test_counter_never_zero() {
        let zero = StorePacking::<Counter, felt252>::pack(Counter { value: 0 });
        assert(zero == LIVE, 'zero is LIVE');
        let max = Counter { value: 0xFFFFFFFFFFFFFFFF };
        let word = StorePacking::<Counter, felt252>::pack(max);
        assert(StorePacking::<Counter, felt252>::unpack(word) == max, 'round trip');
        assert(PackingTrait::join(0, 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0, 'widest high limb');
    }

    #[test]
    #[should_panic(expected: 'packing: high limb overflow')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_join_refuses_live_overflow() {
        PackingTrait::join(0, 0x4000000000000000000000000000000);
    }

    #[test]
    #[should_panic(expected: 'packing: bitmap above bit 249')]
    #[available_gas(l2_gas: 10385)] // ceil(1.05 × 9890 measured)
    fn test_bitmap_above_249_refused() {
        let bit250: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
        StorePacking::<Bitmap, felt252>::pack(Bitmap { bits: bit250 });
    }
}
