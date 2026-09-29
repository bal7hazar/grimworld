//! Packing of records into one felt (docs/CAIRO.md §4; docs/architecture/ENG-01-interfaces.md,
//! *Packing*). Every layout of the game follows three rules:
//! - a field never straddles bit 128, so that a record is read as two `u128` limbs;
//! - bit 250 (`LIVE`) is set in every stored record, so that a reused slot never holds 0: the
//!   local node prices a key written again after it held 0 as a new slot, about 14 times an
//!   overwrite (ENG-01, *Reuse, measured*);
//! - bits 251 and up do not exist (a felt is below 2^251 + 17·2^192 + 1).
//!
//! `u256` is used only to split a felt into its two limbs (written reason: the cheapest split on
//! Cairo 2.19; ENG-02 may replace it by `u252` from `origami_hexmap`).

/// Bit 250, set in every stored record: a stored slot is never 0.
pub const LIVE: felt252 = 0x400000000000000000000000000000000000000000000000000000000000000;
/// `LIVE` as seen in the high limb (bit 122 of it).
pub const LIVE_HIGH: u128 = 0x4000000000000000000000000000000;
/// 2^128.
pub const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;

/// The two limbs of a stored record, `LIVE` removed from the high one.
#[inline(always)]
pub fn split(word: felt252) -> (u128, u128) {
    let wide: u256 = word.into();
    let high = if wide.high >= LIVE_HIGH {
        wide.high - LIVE_HIGH
    } else {
        wide.high
    };
    (wide.low, high)
}

/// A stored record from its two limbs, `LIVE` set. `high` must be below 2^122: a field that
/// overflows into `LIVE` or beyond is refused, never written.
#[inline(always)]
pub fn join(low: u128, high: u128) -> felt252 {
    assert(high < LIVE_HIGH, 'packing: high limb overflow');
    low.into() + high.into() * TWO_POW_128 + LIVE
}

/// Refuses a value wider than its field (`size = 2^width`): a packer checks every field narrower
/// than its Cairo type, so that it can never corrupt its neighbour (ENG-01 fix loop 1, F-9).
#[inline(always)]
pub fn fits(value: u128, size: u128, message: felt252) {
    assert(value < size, message);
}

/// The field of `limb` at bit `2^offset = shift`, of width `2^width = size`.
#[inline(always)]
pub fn field(limb: u128, shift: u128, size: u128) -> u128 {
    let (above, _) = DivRem::div_rem(limb, shift.try_into().unwrap());
    let (_, value) = DivRem::div_rem(above, size.try_into().unwrap());
    value
}

/// The byte of `limb` at bit `2^offset = shift`.
#[inline(always)]
pub fn byte_at(limb: u128, shift: u128) -> u8 {
    field(limb, shift, 0x100).try_into().unwrap()
}

/// The `u16` of `limb` at bit `2^offset = shift`.
#[inline(always)]
pub fn u16_at(limb: u128, shift: u128) -> u16 {
    field(limb, shift, 0x10000).try_into().unwrap()
}

/// The `u32` of `limb` at bit `2^offset = shift`.
#[inline(always)]
pub fn u32_at(limb: u128, shift: u128) -> u32 {
    field(limb, shift, 0x100000000).try_into().unwrap()
}

/// The low field of `limb`, of width `2^width = size`.
#[inline(always)]
pub fn low_field(limb: u128, size: NonZero<u128>) -> u128 {
    let (_, value) = DivRem::div_rem(limb, size);
    value
}

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

pub fn pack_lanes32(value: Lanes32) -> felt252 {
    let [a, b, c, d, e, f, g] = value.lanes;
    let low: u128 = a.into() + b.into() * P32 + c.into() * P64 + d.into() * P96;
    let high: u128 = e.into() + f.into() * P32 + g.into() * P64;
    join(low, high)
}

pub fn unpack_lanes32(word: felt252) -> Lanes32 {
    let (low, high) = split(word);
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

pub impl Lanes32StorePacking of starknet::storage_access::StorePacking<Lanes32, felt252> {
    fn pack(value: Lanes32) -> felt252 {
        pack_lanes32(value)
    }
    fn unpack(value: felt252) -> Lanes32 {
        unpack_lanes32(value)
    }
}

/// Fifteen `u16` lanes in one felt: lanes 0 to 7 in the low limb, 8 to 14 in the high one (bits
/// 128 to 239). Used for lists of entity ids and of `u16` content ids.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Lanes16 {
    pub lanes: [u16; 15],
}

pub fn pack_lanes16(value: Lanes16) -> felt252 {
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
    join(low, high)
}

pub fn unpack_lanes16(word: felt252) -> Lanes16 {
    let (low, high) = split(word);
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
        *out[0], *out[1], *out[2], *out[3], *out[4], *out[5], *out[6], *out[7], *out[8], *out[9],
        *out[10], *out[11], *out[12], *out[13], *out[14],
    ];
    Lanes16 { lanes }
}

pub impl Lanes16StorePacking of starknet::storage_access::StorePacking<Lanes16, felt252> {
    fn pack(value: Lanes16) -> felt252 {
        pack_lanes16(value)
    }
    fn unpack(value: felt252) -> Lanes16 {
        unpack_lanes16(value)
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
        join(value.value.into(), 0)
    }
    fn unpack(value: felt252) -> Counter {
        let (low, _) = split(value);
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
        let (low, high) = split(value);
        Bitmap { bits: low.into() + high.into() * TWO_POW_128 }
    }
}
