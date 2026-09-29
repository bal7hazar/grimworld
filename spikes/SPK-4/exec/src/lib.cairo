//! The executables of SPK-4 over the pure library `spk4` (its `exec::run` decodes a case).

use spk4::exec::run;

/// One action, as the client calls it: the case in, its result out.
#[executable]
fn step(case: Array<felt252>) -> Array<felt252> {
    run(case.span())
}

/// Many cases, `[len, case...]` each, run in order; each result is printed as soon as it is
/// computed, so that the cases before a panic are known (spikes/SPK-4/generate.py).
#[executable]
fn batch(cases: Array<felt252>) -> u32 {
    let mut cases = cases.span();
    let mut count: u32 = 0;
    while let Some(len) = cases.pop_front() {
        let len: u32 = (*len).try_into().unwrap();
        let case = cases.slice(0, len);
        cases = cases.slice(len, cases.len() - len);
        let result = run(case);
        println!("r {:?}", result);
        count += 1;
    }
    count
}
