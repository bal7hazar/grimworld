//! Native baseline of the runner.
//!
//!   spk4-run <executable.json> args <felts>        one run, its outcome as JSON
//!   spk4-run <executable.json> vectors <file>      every vector through `step`, compared

use std::time::Instant;

use spk4_runner::{outcome_json, parse_felts, Executable};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 4 {
        eprintln!("usage: spk4-run <executable.json> (args <felts> | vectors <file>)");
        std::process::exit(2);
    }
    let t = Instant::now();
    let exe = Executable::load(&std::fs::read_to_string(&a[1]).expect("read executable")).expect("load");
    let load_ms = t.elapsed().as_secs_f64() * 1e3;
    match a[2].as_str() {
        "args" => {
            let o = exe.run(&parse_felts(&a[3]).expect("felts")).expect("run");
            println!("{}", outcome_json(&o));
        }
        "vectors" => {
            let text = std::fs::read_to_string(&a[3]).expect("read vectors");
            let (mut n, mut diverge, mut steps) = (0usize, 0usize, 0usize);
            let t = Instant::now();
            for line in text.lines().filter(|l| !l.is_empty()) {
                let v: serde_json::Value = serde_json::from_str(line).expect("vector");
                let case: Vec<_> = v["case"].as_array().unwrap().iter().map(|x| x.as_str().unwrap()).collect();
                // The arguments of `main`, serialized: the array's length, then its felts.
                let args = format!("{},{}", case.len(), case.join(","));
                let o = exe.run(&parse_felts(&args).unwrap()).expect("run");
                let hex = |x: &serde_json::Value| -> Vec<String> {
                    x.as_array().unwrap().iter().map(|f| f.as_str().unwrap().to_string()).collect()
                };
                let got = match &o.result {
                    // `step` returns an Array<felt252>: its length, then the felts.
                    Ok(r) => ("ok", r.iter().skip(1).map(|f| f.to_hex_string()).collect::<Vec<_>>()),
                    Err(p) => ("panic", p.iter().map(|f| f.to_hex_string()).collect()),
                };
                let want = if v.get("ok").is_some() { ("ok", hex(&v["ok"])) } else { ("panic", hex(&v["panic"])) };
                if got != want {
                    diverge += 1;
                    if diverge <= 10 {
                        eprintln!("#{} {:?} != {:?}", v["id"], got, want);
                    }
                }
                steps += o.steps;
                n += 1;
            }
            let ms = t.elapsed().as_secs_f64() * 1e3;
            println!(
                "{{\"vectors\":{n},\"divergences\":{diverge},\"load_ms\":{load_ms:.1},\"run_ms\":{ms:.1},\"per_call_us\":{:.1},\"mean_steps\":{:.1}}}",
                ms * 1e3 / n as f64,
                steps as f64 / n as f64
            );
        }
        _ => {
            eprintln!("unknown mode {}", a[2]);
            std::process::exit(2);
        }
    }
}
