//! SPK-13: prints a Sierra program as text, with its debug names, so that two builds of the same
//! sources can be diffed.
//!
//!   sierra-dump class <x.contract_class.json>   the program of a Starknet class (its felts
//!                                               decoded, the names of `sierra_program_debug_info`)
//!   sierra-dump test <x.test.sierra.json>       a compiled test file (a Sierra program artifact)
//!
//! A type or libfunc without a debug name (the compiled test files carry the names of the user
//! functions only) is named after its long id, resolved recursively (`Array<felt252>`), so that
//! the text does not depend on the numbers the compiler gave the ids.
use std::collections::HashMap;
use std::fs;

use cairo_lang_sierra::debug_info::DebugInfo;
use cairo_lang_sierra::ids::{ConcreteLibfuncId, ConcreteTypeId};
use cairo_lang_sierra::program::{GenericArg, Program, VersionedProgram};
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

/// Names every unnamed type and libfunc after its long id.
fn name_from_long_ids(program: &mut Program) {
    let types: HashMap<u64, _> =
        program.type_declarations.iter().map(|d| (d.id.id, d.clone())).collect();
    let funcs: HashMap<u64, String> = program
        .funcs
        .iter()
        .filter_map(|f| f.id.debug_name.as_ref().map(|n| (f.id.id, n.to_string())))
        .collect();
    let mut type_names: HashMap<u64, String> = HashMap::new();
    fn type_name(
        id: &ConcreteTypeId,
        types: &HashMap<u64, cairo_lang_sierra::program::TypeDeclaration>,
        memo: &mut HashMap<u64, String>,
    ) -> String {
        if let Some(name) = &id.debug_name {
            return name.to_string();
        }
        if let Some(name) = memo.get(&id.id) {
            return name.clone();
        }
        let Some(decl) = types.get(&id.id) else { return format!("[{}]", id.id) };
        if let Some(name) = &decl.id.debug_name {
            return name.to_string();
        }
        let args: Vec<String> =
            decl.long_id.generic_args.iter().map(|a| arg_name(a, types, &HashMap::new(), memo)).collect();
        let name = if args.is_empty() {
            decl.long_id.generic_id.to_string()
        } else {
            format!("{}<{}>", decl.long_id.generic_id, args.join(", "))
        };
        memo.insert(id.id, name.clone());
        name
    }
    fn arg_name(
        arg: &GenericArg,
        types: &HashMap<u64, cairo_lang_sierra::program::TypeDeclaration>,
        funcs: &HashMap<u64, String>,
        memo: &mut HashMap<u64, String>,
    ) -> String {
        match arg {
            GenericArg::Type(t) => type_name(t, types, memo),
            GenericArg::UserFunc(f) if f.debug_name.is_none() && funcs.contains_key(&f.id) => {
                format!("user@{}", funcs[&f.id])
            }
            other => other.to_string(),
        }
    }
    let mut info = DebugInfo::default();
    for decl in &program.type_declarations {
        let name = type_name(&decl.id, &types, &mut type_names);
        info.type_names.insert(ConcreteTypeId::new(decl.id.id), name.into());
    }
    for decl in &program.libfunc_declarations {
        let name = decl.id.debug_name.as_ref().map(|n| n.to_string()).unwrap_or_else(|| {
            let args: Vec<String> = decl
                .long_id
                .generic_args
                .iter()
                .map(|a| arg_name(a, &types, &funcs, &mut type_names))
                .collect();
            if args.is_empty() {
                decl.long_id.generic_id.to_string()
            } else {
                format!("{}<{}>", decl.long_id.generic_id, args.join(", "))
            }
        });
        info.libfunc_names.insert(ConcreteLibfuncId::new(decl.id.id), name.into());
    }
    for f in &program.funcs {
        if let Some(name) = &f.id.debug_name {
            info.user_func_names.insert(f.id.clone(), name.clone());
        }
    }
    info.populate(program);
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut program = match (args.get(1).map(String::as_str), args.get(2)) {
        (Some("class"), Some(path)) => class(path),
        (Some("test"), Some(path)) => test(path),
        _ => {
            eprintln!("usage: sierra-dump <class|test> <file.json>");
            std::process::exit(2);
        }
    };
    name_from_long_ids(&mut program);
    print!("{program}");
}
