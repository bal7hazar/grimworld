//! The recorders of `vectors/segment2.jsonl` (RV-02, D-254): test classes that stand in for
//! `TickLibrary`, `ActionLibrary` and `TrapLibrary` in a segment's `Classes`, forward each call to
//! the real class, and log what it returns, so that a row carries the classes' results as data
//! and a mirror replays `SegmentTrait::run` around them. Test code only.
//!
//! A library call runs in the caller's context: the recorders keep their state in the test's own
//! storage, through raw syscalls at fixed addresses (`REAL_*`, `DEPTH`, `COUNT`, `LOG`). Only the
//! segment's own calls are logged (`DEPTH` 0): `TickLibrary` calls the trap class it is given,
//! which is the trap recorder, and that nested call is forwarded unlogged.

use core::poseidon::poseidon_hash_span;
use starknet::storage_access::StorageAddress;
use starknet::syscalls::{storage_read_syscall, storage_write_syscall};
use starknet::{ClassHash, SyscallResultTrait};
use crate::models::chunk::Features;
use crate::types::action::Illegal;
use crate::types::world::Words;

/// The real classes' hashes, the nesting depth, the calls logged and their felts.
pub const REAL_TICK: felt252 = 'rv02.real.tick';
pub const REAL_ACTION: felt252 = 'rv02.real.action';
pub const REAL_TRAP: felt252 = 'rv02.real.trap';
const DEPTH: felt252 = 'rv02.depth';
const COUNT: felt252 = 'rv02.count';
const LENGTH: felt252 = 'rv02.length';
const LOG: felt252 = 'rv02.log';

/// One call of the segment to a class, in order: the Poseidon hash of its inputs' `Serde` felts
/// (all but the content and the class hashes, the table's environment), then what it returned.
#[derive(Drop, Serde, Clone, Debug, PartialEq)]
pub enum Call {
    /// `TickLibrary::ticks(words, content, board, classes, level, ground, n)`: the inputs hashed
    /// are `words, board, level, ground, n`.
    Tick: (felt252, Words, Array<(u8, Features)>),
    /// `ActionLibrary::act(words, content, board, executor, ground, action)`: `words, board,
    /// ground, action`.
    Act: (felt252, Words, Array<(u8, Features)>, Result<u8, Illegal>),
    /// `TrapLibrary::trigger(words, content, board, ground, entrant, position, level)`: `words,
    /// board, ground, entrant, position, level`.
    Trap: (felt252, Words, Array<(u8, Features)>, bool),
}

fn address(key: felt252) -> StorageAddress {
    key.try_into().unwrap()
}

pub fn read(key: felt252) -> felt252 {
    storage_read_syscall(0, address(key)).unwrap_syscall()
}

pub fn write(key: felt252, value: felt252) {
    storage_write_syscall(0, address(key), value).unwrap_syscall();
}

pub fn real(key: felt252) -> ClassHash {
    read(key).try_into().unwrap()
}

/// Enters a call: whether it is the segment's own (to log).
pub fn enter() -> bool {
    let depth = read(DEPTH);
    write(DEPTH, depth + 1);
    depth == 0
}

pub fn leave() {
    write(DEPTH, read(DEPTH) - 1);
}

pub fn digest(inputs: @Array<felt252>) -> felt252 {
    poseidon_hash_span(inputs.span())
}

/// Logs `call` after the ones before it.
pub fn log(call: @Call) {
    let mut felts = array![];
    call.serialize(ref felts);
    let mut at = read(LENGTH);
    for felt in felts {
        write(LOG + at, felt);
        at += 1;
    }
    write(LENGTH, at);
    write(COUNT, read(COUNT) + 1);
}

/// Sets the real classes and clears the log.
pub fn reset(tick: ClassHash, action: ClassHash, trap: ClassHash) {
    write(REAL_TICK, tick.into());
    write(REAL_ACTION, action.into());
    write(REAL_TRAP, trap.into());
    write(DEPTH, 0);
    write(COUNT, 0);
    write(LENGTH, 0);
}

/// The calls logged since `reset`, as `Serde` felts of `Array<Call>`.
pub fn calls() -> Array<felt252> {
    let mut felts = array![read(COUNT)];
    let length = read(LENGTH);
    let mut at = 0;
    while at != length {
        felts.append(read(LOG + at));
        at += 1;
    }
    felts
}

#[starknet::contract]
pub mod TickRecorder {
    use crate::interface::{
        ITickLibrary, ITickLibraryDispatcherTrait, ITickLibraryLibraryDispatcher,
    };
    use crate::models::chunk::Features;
    use crate::types::executor::Board;
    use crate::types::play::Classes;
    use crate::types::tick::Content;
    use crate::types::world::Words;
    use super::{Call, REAL_TICK, digest, enter, leave, log, real};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl TickRecorderImpl of ITickLibrary<ContractState> {
        fn ticks(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            classes: Classes,
            level: u8,
            ground: Array<(u8, Features)>,
            ticks: u8,
        ) -> (Words, Array<(u8, Features)>) {
            let own = enter();
            let mut inputs = array![];
            words.serialize(ref inputs);
            board.serialize(ref inputs);
            level.serialize(ref inputs);
            ground.serialize(ref inputs);
            ticks.serialize(ref inputs);
            let (out, ground) = ITickLibraryLibraryDispatcher { class_hash: real(REAL_TICK) }
                .ticks(words, content, board, classes, level, ground, ticks);
            leave();
            if own {
                log(@Call::Tick((digest(@inputs), out.clone(), ground.clone())));
            }
            (out, ground)
        }
    }
}

#[starknet::contract]
pub mod ActionRecorder {
    use starknet::ClassHash;
    use crate::actions::Action;
    use crate::interface::{
        IActionLibrary, IActionLibraryDispatcherTrait, IActionLibraryLibraryDispatcher,
    };
    use crate::models::chunk::Features;
    use crate::types::action::Illegal;
    use crate::types::executor::Board;
    use crate::types::tick::Content;
    use crate::types::world::Words;
    use super::{Call, REAL_ACTION, digest, enter, leave, log, real};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl ActionRecorderImpl of IActionLibrary<ContractState> {
        fn act(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            executor: ClassHash,
            ground: Array<(u8, Features)>,
            action: Action,
        ) -> (Words, Array<(u8, Features)>, Result<u8, Illegal>) {
            let own = enter();
            let mut inputs = array![];
            words.serialize(ref inputs);
            board.serialize(ref inputs);
            ground.serialize(ref inputs);
            action.serialize(ref inputs);
            let (out, ground, result) = IActionLibraryLibraryDispatcher {
                class_hash: real(REAL_ACTION),
            }
                .act(words, content, board, executor, ground, action);
            leave();
            if own {
                log(@Call::Act((digest(@inputs), out.clone(), ground.clone(), result)));
            }
            (out, ground, result)
        }
    }
}

#[starknet::contract]
pub mod TrapRecorder {
    use crate::interface::{
        ITrapLibrary, ITrapLibraryDispatcherTrait, ITrapLibraryLibraryDispatcher,
    };
    use crate::models::chunk::Features;
    use crate::types::executor::Board;
    use crate::types::tick::Content;
    use crate::types::world::Words;
    use super::{Call, REAL_TRAP, digest, enter, leave, log, real};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl TrapRecorderImpl of ITrapLibrary<ContractState> {
        fn trigger(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            ground: Array<(u8, Features)>,
            entrant: u16,
            position: u8,
            level: u8,
        ) -> (Words, Array<(u8, Features)>, bool) {
            let own = enter();
            let mut inputs = array![];
            words.serialize(ref inputs);
            board.serialize(ref inputs);
            ground.serialize(ref inputs);
            entrant.serialize(ref inputs);
            position.serialize(ref inputs);
            level.serialize(ref inputs);
            let (out, ground, triggered) = ITrapLibraryLibraryDispatcher {
                class_hash: real(REAL_TRAP),
            }
                .trigger(words, content, board, ground, entrant, position, level);
            leave();
            if own {
                log(@Call::Trap((digest(@inputs), out.clone(), ground.clone(), triggered)));
            }
            (out, ground, triggered)
        }
    }
}
