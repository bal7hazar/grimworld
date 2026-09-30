//! Unit costs behind the window's figure, 100 iterations each, against the loop alone.

use hexx::board::bits::Bits;
use spk14::tables::{BELOW128, ROW};

#[inline(never)]
fn seed() -> u8 {
    7
}

#[test]
fn micro_loop_baseline() {
    let mut i: u8 = seed();
    let mut acc: u128 = 0;
    while i != 107 {
        acc += i.into();
        i += 1;
    }
    assert!(acc != 0);
}

#[test]
fn micro_row_lookup() {
    let mut i: u8 = seed();
    let mut acc: u128 = 0;
    while i != 107 {
        let (first, _, _) = *ROW.span()[(i % 17).into()];
        acc += i.into() + first.into();
        i += 1;
    }
    assert!(acc != 0);
}

#[test]
fn micro_below_lookup() {
    let mut i: u8 = seed();
    let mut acc: u128 = 0;
    while i != 107 {
        acc += i.into() + *BELOW128.span()[i.into()] % 3;
        i += 1;
    }
    assert!(acc != 0);
}

#[test]
fn micro_pow_lookup() {
    let mut i: u8 = seed();
    let mut acc: felt252 = 0;
    while i != 107 {
        acc += i.into() + Bits::pow(i);
        i += 1;
    }
    assert!(acc != 0);
}

#[test]
fn micro_slot_lookup() {
    let slots: [(u128, u128); 12] = [
        (1, 2), (3, 4), (5, 6), (7, 8), (9, 10), (11, 12), (13, 14), (15, 16), (17, 18), (19, 20),
        (21, 22), (23, 24),
    ];
    let slots = slots.span();
    let mut i: u8 = seed();
    let mut acc: u128 = 0;
    while i != 107 {
        let (low, _) = *slots[(i % 12).into()];
        acc += i.into() + low;
        i += 1;
    }
    assert!(acc != 0);
}

#[test]
fn micro_mod_baseline() {
    let mut i: u8 = seed();
    let mut acc: u128 = 0;
    while i != 107 {
        acc += i.into() + (i % 17).into();
        i += 1;
    }
    assert!(acc != 0);
}
