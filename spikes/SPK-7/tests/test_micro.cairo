use origami_hexmap::helpers::bits::Bits;

#[test]
#[available_gas(l2_gas: 4000000000)]
fn micro_loop_baseline() {
    let mut i: u8 = 0;
    let mut acc: felt252 = 0;
    while i != 100 {
        acc += i.into();
        i += 1;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn micro_pow() {
    let mut i: u8 = 0;
    let mut acc: felt252 = 0;
    while i != 100 {
        acc += Bits::pow(i);
        i += 1;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 4000000000)]
fn micro_get() {
    let mut i: u8 = 0;
    let mut acc: felt252 = 0;
    let v: u256 = 0x123456789abcdef0123456789abcdef0123456789abcdef;
    while i != 100 {
        if Bits::get(v, i) {
            acc += 1;
        }
        acc += i.into();
        i += 1;
    }
    assert!(acc != 0);
}
