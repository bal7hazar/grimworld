// Kept apart from src/lib.cairo (not under `#[cfg(test)]` there, docs/CAIRO.md §2 D-167) so that
// src/lib.cairo stays, line for line, the program of issue-draft.md.
use spk13_minimal::b::pong;
use spk13_minimal::ping;

#[test]
#[available_gas(l2_gas: 35931)]
fn test_ping_pong_alternate() {
    // ping(n) ends in ping(0) = 0 when n is even and in pong(0) = 1 when n is odd.
    assert_eq!(ping(0), 0);
    assert_eq!(ping(5), 1);
    assert_eq!(pong(4), 1);
    assert_eq!(pong(7), 0);
}
