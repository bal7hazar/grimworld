//! SPK-4 option (b): runs a Scarb 2.19 executable (`<name>.executable.json`: CASM and hints) on
//! cairo-vm 3.2.0, the same artifact `scarb execute` runs, natively or compiled to WebAssembly.
//!
//! The core hints go to cairo-vm's `Cairo1HintProcessor`. The executable's wrapper adds four hints
//! the VM does not know, handled here: `WriteRunParam` (the arguments), `AddMarker` (the panic
//! data), `AddRelocationRule` (dictionaries' segments) and `DebugPrint` (`println!`, collected as
//! text). The approach follows the owner's physics-game spike (slingfall docs/research/03), rebuilt
//! for this spike.

use std::any::Any;
use std::collections::HashMap;
use std::sync::Arc;

use cairo_lang_casm::hints::Hint;
use cairo_lang_casm::operand::{CellRef, DerefOrImmediate, Operation, Register, ResOperand};
use cairo_vm::hint_processor::cairo_1_hint_processor::hint_processor::Cairo1HintProcessor;
use cairo_vm::hint_processor::hint_processor_definition::{HintProcessorLogic, HintReference};
use cairo_vm::serde::deserialize_program::{ApTracking, FlowTrackingData, HintParams, ReferenceManager};
use cairo_vm::types::builtin_name::BuiltinName;
use cairo_vm::types::exec_scope::ExecutionScopes;
use cairo_vm::types::layout_name::LayoutName;
use cairo_vm::types::program::Program;
use cairo_vm::types::relocatable::{MaybeRelocatable, Relocatable};
use cairo_vm::vm::errors::hint_errors::HintError;
use cairo_vm::vm::errors::vm_errors::VirtualMachineError;
use cairo_vm::vm::runners::cairo_runner::{CairoRunner, ResourceTracker, RunResources};
use cairo_vm::vm::vm_core::VirtualMachine;
use cairo_vm::Felt252;
use serde_json::Value;

#[cfg(target_arch = "wasm32")]
mod wasm;

fn err<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}

#[derive(Clone, Debug)]
enum ExecHint {
    Core(Hint),
    WriteRunParam { index: ResOperand, dst: CellRef },
    AddMarker { start: ResOperand, end: ResOperand },
    AddRelocationRule { src: ResOperand, dst: ResOperand },
    DebugPrint { start: ResOperand, end: ResOperand },
}

fn field<T: serde::de::DeserializeOwned>(v: &Value, k: &str) -> Result<T, String> {
    serde_json::from_value(v.get(k).cloned().ok_or(format!("hint without {k}"))?).map_err(err)
}

fn parse_hint(v: &Value) -> Result<ExecHint, String> {
    let (name, body) = v.as_object().and_then(|o| o.iter().next()).ok_or("malformed hint")?;
    Ok(match name.as_str() {
        "WriteRunParam" => ExecHint::WriteRunParam { index: field(body, "index")?, dst: field(body, "dst")? },
        "AddMarker" => ExecHint::AddMarker { start: field(body, "start")?, end: field(body, "end")? },
        "AddRelocationRule" => ExecHint::AddRelocationRule { src: field(body, "src")?, dst: field(body, "dst")? },
        "DebugPrint" => ExecHint::DebugPrint { start: field(body, "start")?, end: field(body, "end")? },
        _ => ExecHint::Core(serde_json::from_value(v.clone()).map_err(|e| format!("{name}: {e}"))?),
    })
}

/// A loaded executable, parsed once and run many times.
pub struct Executable {
    program: Program,
    hints: HashMap<usize, Vec<ExecHint>>,
    core_hints: Vec<(usize, Vec<Hint>)>,
    pub bytecode_len: usize,
}

/// What a run gives back.
#[derive(Debug)]
pub struct Outcome {
    /// `Ok(felts)`: what `main` returned, serialized; `Err(felts)`: the panic data.
    pub result: Result<Vec<Felt252>, Vec<Felt252>>,
    /// Lines printed by `println!`.
    pub prints: Vec<String>,
    pub steps: usize,
    pub memory_cells: usize,
}

impl Executable {
    /// Parses `executable.json` and builds the program of its `Bootloader` entrypoint, the plain
    /// execution `scarb execute` runs by default.
    pub fn load(json: &str) -> Result<Executable, String> {
        let v: Value = serde_json::from_str(json).map_err(err)?;
        let prog = &v["program"];
        let data: Vec<MaybeRelocatable> = prog["bytecode"]
            .as_array()
            .ok_or("no bytecode")?
            .iter()
            .map(|x| {
                let s = x.as_str().ok_or("bytecode entry is not a string")?;
                // Negative immediates are written "-0x..".
                let f = match s.strip_prefix('-') {
                    Some(p) => Felt252::from_hex(p).map(|f| -f),
                    None => Felt252::from_hex(s),
                };
                f.map(MaybeRelocatable::from).map_err(err)
            })
            .collect::<Result<_, String>>()?;
        let mut hints = HashMap::new();
        let mut params = HashMap::new();
        for entry in prog["hints"].as_array().ok_or("no hints")? {
            let pc = entry[0].as_u64().ok_or("hint without pc")? as usize;
            let hs = entry[1].as_array().ok_or("malformed hints")?.iter().map(parse_hint).collect::<Result<Vec<_>, _>>()?;
            hints.insert(pc, hs);
            // The hint's "code" is its pc: `compile_hint` looks the hints up by it.
            params.insert(
                pc,
                vec![HintParams {
                    code: pc.to_string(),
                    accessible_scopes: vec![],
                    flow_tracking_data: FlowTrackingData { ap_tracking: ApTracking::default(), reference_ids: HashMap::new() },
                }],
            );
        }
        let ep = v["entrypoints"]
            .as_array()
            .ok_or("no entrypoints")?
            .iter()
            .find(|e| e["kind"] == "Bootloader")
            .ok_or("no Bootloader entrypoint")?;
        let offset = ep["offset"].as_u64().ok_or("entrypoint without offset")? as usize;
        let builtins: Vec<BuiltinName> = ep["builtins"]
            .as_array()
            .ok_or("entrypoint without builtins")?
            .iter()
            .map(|b| b.as_str().and_then(BuiltinName::from_str).ok_or("unknown builtin".to_string()))
            .collect::<Result<_, _>>()?;
        let bytecode_len = data.len();
        let program = Program::new(builtins, data, Some(offset), params, ReferenceManager { references: vec![] }, HashMap::new(), vec![], None)
            .map_err(err)?;
        let core_hints = hints
            .iter()
            .map(|(pc, hs)| (*pc, hs.iter().filter_map(|h| if let ExecHint::Core(c) = h { Some(c.clone()) } else { None }).collect()))
            .collect();
        Ok(Executable { program, hints, core_hints, bytecode_len })
    }

    /// Runs `main` with `args`, the felts of its single `Array<felt252>` argument.
    pub fn run(&self, args: &[Felt252]) -> Result<Outcome, String> {
        let mut hp = Processor {
            // `true`: dictionaries after the first live in temporary segments, which the wrapper
            // relocates with `AddRelocationRule`, as cairo-lang-runner does.
            inner: Cairo1HintProcessor::new(&self.core_hints, RunResources::default(), true),
            hints: &self.hints,
            args,
            markers: vec![],
            prints: vec![],
        };
        let mut runner = CairoRunner::new(&self.program, LayoutName::all_cairo, None, false, false, false).map_err(err)?;
        let end = runner.initialize(false).map_err(err)?;
        let run = runner.run_until_pc(end, &mut hp);
        let steps = runner.vm.get_current_step();
        if let Err(e) = run {
            // A panic: the wrapper marked its data (`AddMarker`) before failing.
            return match hp.markers.pop() {
                Some(data) => Ok(Outcome { result: Err(data), prints: hp.prints, steps, memory_cells: 0 }),
                None => Err(format!("run failed without a panic: {e}")),
            };
        }
        runner.end_run(false, false, &mut hp, false).map_err(err)?;
        runner.read_return_values(false).map_err(err)?;
        cairo_vm::vm::security::verify_secure_runner(&runner, true, None).map_err(err)?;
        let resources = runner.get_execution_resources().map_err(err)?;
        let memory_cells = runner.vm.segments.compute_effective_sizes().iter().sum();
        let mut text = String::new();
        runner.vm.write_output(&mut text).map_err(err)?;
        let output: Vec<Felt252> = text
            .lines()
            .filter_map(|l| l.trim().parse::<num_bigint::BigInt>().ok())
            .map(|b| Felt252::from(&b))
            .collect();
        // The output builtin holds the serialized return value (a panic ended the run above).
        Ok(Outcome { result: Ok(output), prints: hp.prints, steps: resources.n_steps, memory_cells })
    }
}

struct Processor<'a> {
    inner: Cairo1HintProcessor,
    hints: &'a HashMap<usize, Vec<ExecHint>>,
    args: &'a [Felt252],
    markers: Vec<Vec<Felt252>>,
    prints: Vec<String>,
}

fn cell(vm: &VirtualMachine, c: &CellRef) -> Result<Relocatable, HintError> {
    let base = match c.register {
        Register::AP => vm.get_ap(),
        Register::FP => vm.get_fp(),
    };
    Ok((base + c.offset as i32)?)
}

fn value(vm: &VirtualMachine, r: &ResOperand) -> Result<MaybeRelocatable, HintError> {
    let at = |c: &CellRef| -> Result<MaybeRelocatable, HintError> {
        let a = cell(vm, c)?;
        vm.get_maybe(&a).ok_or_else(|| HintError::from(VirtualMachineError::InvalidMemoryValueTemporaryAddress(Box::new(a))))
    };
    Ok(match r {
        ResOperand::Deref(c) => at(c)?,
        ResOperand::Immediate(x) => MaybeRelocatable::from(Felt252::from(&x.value)),
        ResOperand::BinOp(op) => {
            let a = at(&op.a)?;
            let b = match &op.b {
                DerefOrImmediate::Deref(c) => at(c)?,
                DerefOrImmediate::Immediate(x) => MaybeRelocatable::from(Felt252::from(&x.value)),
            };
            match op.op {
                Operation::Add => a.add(&b).map_err(|e| HintError::CustomHint(e.to_string().into()))?,
                Operation::Mul => match (a, b) {
                    (MaybeRelocatable::Int(a), MaybeRelocatable::Int(b)) => MaybeRelocatable::from(a * b),
                    _ => return Err(HintError::CustomHint("product of pointers".into())),
                },
            }
        }
        ResOperand::DoubleDeref(c, off) => {
            let p = vm.get_relocatable(cell(vm, c)?)?;
            let a = (p + *off as i32)?;
            vm.get_maybe(&a).ok_or(HintError::CustomHint("double deref".into()))?
        }
    })
}

fn pointer(vm: &VirtualMachine, r: &ResOperand) -> Result<Relocatable, HintError> {
    match value(vm, r)? {
        MaybeRelocatable::RelocatableValue(p) => Ok(p),
        _ => Err(HintError::CustomHint("expected a pointer".into())),
    }
}

fn felts(vm: &VirtualMachine, start: &ResOperand, end: &ResOperand) -> Result<Vec<Felt252>, HintError> {
    let (mut s, e) = (pointer(vm, start)?, pointer(vm, end)?);
    let mut out = vec![];
    while s != e {
        out.push(*vm.get_integer(s)?);
        s += 1;
    }
    Ok(out)
}

impl Processor<'_> {
    fn exec(&mut self, vm: &mut VirtualMachine, scopes: &mut ExecutionScopes, h: &ExecHint) -> Result<(), HintError> {
        match h {
            ExecHint::Core(h) => self.inner.execute(vm, scopes, h),
            ExecHint::WriteRunParam { index, dst } => {
                // One parameter, the `Array<felt252>` of `main`: its (start, end) in a new segment.
                if value(vm, index)? != MaybeRelocatable::from(0) {
                    return Err(HintError::CustomHint("only one run parameter".into()));
                }
                let seg = vm.add_memory_segment();
                for (i, a) in self.args.iter().enumerate() {
                    vm.insert_value((seg + i)?, *a)?;
                }
                let d = cell(vm, dst)?;
                vm.insert_value(d, seg)?;
                vm.insert_value((d + 1)?, (seg + self.args.len())?)?;
                Ok(())
            }
            ExecHint::AddMarker { start, end } => {
                let m = felts(vm, start, end)?;
                self.markers.push(m);
                Ok(())
            }
            ExecHint::AddRelocationRule { src, dst } => {
                let (s, d) = (pointer(vm, src)?, pointer(vm, dst)?);
                vm.add_relocation_rule(s, d)?;
                Ok(())
            }
            ExecHint::DebugPrint { start, end } => {
                let f = felts(vm, start, end)?;
                self.prints.push(byte_array_text(&f));
                Ok(())
            }
        }
    }
}

impl HintProcessorLogic for Processor<'_> {
    fn compile_hint(
        &self,
        code: &str,
        _: &ApTracking,
        _: &HashMap<String, usize>,
        _: &[HintReference],
        _: &[String],
        _: Arc<HashMap<String, Felt252>>,
    ) -> Result<Box<dyn Any>, VirtualMachineError> {
        let pc: usize = code.parse().map_err(|_| VirtualMachineError::Unexpected)?;
        Ok(Box::new(pc))
    }

    fn execute_hint(&mut self, vm: &mut VirtualMachine, scopes: &mut ExecutionScopes, data: &Box<dyn Any>) -> Result<(), HintError> {
        let pc: usize = *data.downcast_ref().ok_or(HintError::WrongHintData)?;
        let hints = self.hints;
        for h in hints.get(&pc).ok_or(HintError::WrongHintData)? {
            self.exec(vm, scopes, h)?;
        }
        Ok(())
    }
}

impl ResourceTracker for Processor<'_> {}

/// The text of a `println!`: a serialized `ByteArray` after its magic felt (cairo-lang's
/// debug-print format), `[magic, n, word × n, pending word, pending length]`.
pub fn byte_array_text(f: &[Felt252]) -> String {
    const MAGIC: &str = "0x46a6158a16a947e5916b2a2ca68501a45e93d7110e81aa2d6438b1c57c879a3";
    let mut s = String::new();
    let mut i = 0;
    while i < f.len() {
        if f[i].to_hex_string() == MAGIC && i + 1 < f.len() {
            let n: usize = f[i + 1].to_biguint().try_into().unwrap_or(0);
            let mut bytes = vec![];
            for w in &f[i + 2..(i + 2 + n).min(f.len())] {
                bytes.extend_from_slice(&w.to_bytes_be()[1..]);
            }
            if let (Some(pw), Some(pl)) = (f.get(i + 2 + n), f.get(i + 3 + n)) {
                let pl: usize = pl.to_biguint().try_into().unwrap_or(0);
                bytes.extend_from_slice(&pw.to_bytes_be()[32 - pl..]);
            }
            s.push_str(&String::from_utf8_lossy(&bytes));
            i += 4 + n;
        } else {
            s.push_str(&format!("{} ", f[i]));
            i += 1;
        }
    }
    s
}

/// Parses felts written in hex (`0x..`) or decimal, separated by commas or spaces.
pub fn parse_felts(s: &str) -> Result<Vec<Felt252>, String> {
    s.split(|c: char| c == ',' || c.is_whitespace())
        .filter(|x| !x.is_empty())
        .map(|x| if x.starts_with("0x") { Felt252::from_hex(x).map_err(err) } else { Felt252::from_dec_str(x).map_err(err) })
        .collect()
}

/// An outcome as one line of JSON: `{"ok": [..]}` or `{"panic": [..]}` in hex, the prints, the
/// steps and memory cells.
pub fn outcome_json(o: &Outcome) -> String {
    let hex = |v: &[Felt252]| v.iter().map(|f| format!("\"{}\"", f.to_hex_string())).collect::<Vec<_>>().join(",");
    let (kind, felts) = match &o.result {
        Ok(v) => ("ok", hex(v)),
        Err(v) => ("panic", hex(v)),
    };
    let prints = o.prints.iter().map(|p| serde_json::to_string(p).unwrap()).collect::<Vec<_>>().join(",");
    format!("{{\"{kind}\":[{felts}],\"prints\":[{prints}],\"steps\":{},\"memory_cells\":{}}}", o.steps, o.memory_cells)
}
