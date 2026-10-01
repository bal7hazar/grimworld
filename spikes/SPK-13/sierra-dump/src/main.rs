//! SPK-13: prints a Sierra program as text, with its debug names, so that two builds of the same
//! sources can be diffed.
//!
//!   sierra-dump class <x.contract_class.json>   the program of a Starknet class (its felts
//!                                               decoded, the names of `sierra_program_debug_info`)
//!   sierra-dump test <x.test.sierra.json>       a compiled test file (a Sierra program artifact)
use std::fs;

use cairo_lang_sierra::program::{Program, VersionedProgram};
use cairo_lang_starknet_classes::contract_class::ContractClass;

fn class(path: &str) -> Program {
    let class: ContractClass =
        serde_json::from_str(&fs::read_to_string(path).expect("read")).expect("contract class");
    // `true`: the names of `sierra_program_debug_info` replace the bare ids.
    class.extract_sierra_program(true).expect("decode the Sierra felts").program
}

fn test(path: &str) -> Program {
    let versioned: VersionedProgram =
        serde_json::from_str(&fs::read_to_string(path).expect("read")).expect("Sierra program");
    let artifact = versioned.into_v1().expect("version 1");
    let mut program = artifact.program;
    if let Some(info) = &artifact.debug_info {
        info.populate(&mut program);
    }
    program
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let program = match (args.get(1).map(String::as_str), args.get(2)) {
        (Some("class"), Some(path)) => class(path),
        (Some("test"), Some(path)) => test(path),
        _ => {
            eprintln!("usage: sierra-dump <class|test> <file.json>");
            std::process::exit(2);
        }
    };
    print!("{program}");
}
