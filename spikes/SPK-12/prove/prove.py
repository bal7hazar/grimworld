#!/usr/bin/env python3
"""SPK-12: prove segments of the tick on this machine with Stwo, as slingfall proves a level
(github.com/bal7hazar/slingfall, docs/proving.md at f8810c5): the standalone executable `segment`
run and proved by stwo-cairo's own `run_and_prove` (`canonical_small`, binary proof, `--verify`),
then checked again by the separate `verify` binary, which prints the program hash and the public
output the proof commits to.

  spikes/SPK-12/prove/setup.sh --native                 # once: build run_and_prove and verify
  python3 spikes/SPK-12/prove/prove.py --runs 2 --out spikes/SPK-12/prove/out/run1 \
      --case representative:1 --case worst:1 --case representative:10 --case busy:10 ...
  python3 spikes/SPK-12/prove/prove.py --steps-only --case busy:100   # scarb execute alone

A case is `<scenario>:<ticks>`; scenarios are CBT-02's (`segment::fixture`): `representative` (the
representative tick, the pipeline alone), `worst` (`worst_state(true, 3)`: one tick, everything
dies), `busy` (`worst_state(false, 1)` under the `Busy` rules: CBT-02's busy batch).

The script first writes and builds the executables' package (`write_exec`, in the ignored
`prove/out/exec/`). For each case: `scarb execute` of `segment` gives the Cairo steps, the builtins and the header (the
public output); then, per run, `run_and_prove` under `measure` (wall time, the child's peak RSS),
the proof's bytes and sha256, `verify` (exit 0, and its VERIFICATION_OUTPUT's output equal to the
header). Proofs stay in `--out` (git-ignored); `results.json` and `results.txt` hold the figures.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPIKE = HERE.parent
# The executables' package, written by `write_exec` (an executable target needs `enable-gas =
# false`, which the spike's own manifest cannot carry: `snforge test` refuses it).
EXEC = HERE / "out" / "exec"
MANIFEST = EXEC / "Scarb.toml"
TARGET = EXEC / "target" / "dev"
EXEC_MANIFEST = """[package]
name = "spk12_exec"
version = "0.1.0"
edition = "2024_07"
cairo-version = "2.19"

[workspace]

[dependencies]
cairo_execute = "2.19.4"
spk12 = { path = "../../.." }

[[target.executable]]
name = "segment"
function = "spk12_exec::segment"

[[target.executable]]
name = "fixture"
function = "spk12_exec::fixture"

[cairo]
enable-gas = false
"""
EXEC_LIB = """//! SPK-12's executables (written by prove/prove.py): `spk12::segment`'s two functions.

/// The proved segment (`spk12::segment::segment`).
#[executable]
fn segment(
    words: Array<felt252>, content: Array<felt252>, rules: felt252, ticks: u32,
) -> Array<felt252> {
    spk12::segment::segment(words, content, rules, ticks)
}

/// The arguments of `segment` for a scenario (`spk12::segment::fixture`), never proved.
#[executable]
fn fixture(scenario: felt252) -> Array<felt252> {
    spk12::segment::fixture(scenario)
}
"""


def write_exec() -> None:
    """Writes and builds the executables' package."""
    (EXEC / "src").mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(EXEC_MANIFEST)
    (EXEC / "src" / "lib.cairo").write_text(EXEC_LIB)
    subprocess.run(["scarb", "--manifest-path", str(MANIFEST), "build"], check=True)
BIN = HERE / "vendor" / "stwo-cairo" / "stwo_cairo_prover" / "target" / "release"
PARAMS = HERE / "params.canonical_small.json"
P = 2**251 + 17 * 2**192 + 1
SCENARIOS = {"representative": 0, "worst": 1, "busy": 2}
STEPS_RE = re.compile(r"[Nn]um[ _]steps:?\s*(\d+)")
SMALL_TRACE_LIMIT = "is missing from static allocation"


def hexes(felts: list[int]) -> list[str]:
    return [hex(v % P) for v in felts]


def scarb_execute(name: str, args: list[int], args_path: Path) -> tuple[list[int], dict]:
    """`scarb execute` of executable `name`: its program output (felts) and resource usage."""
    args_path.write_text(json.dumps(hexes(args)))
    out = subprocess.run(
        ["scarb", "--manifest-path", str(MANIFEST), "execute", "--no-build", "--output", "none",
         "--executable-name", name, "--arguments-file", str(args_path),
         "--print-program-output", "--print-resource-usage"],
        capture_output=True, text=True,
    )
    text = out.stdout
    if out.returncode != 0 or "Program output:" not in text:
        raise SystemExit(f"scarb execute {name} failed\n{text[-2000:]}\n{out.stderr[-2000:]}")
    body = text.split("Program output:", 1)[1]
    values, usage = body.split("Resources:", 1) if "Resources:" in body else (body, "")
    felts = [int(v) % P for v in values.split()]
    resources = {"raw": " ".join(usage.split())}
    m = re.search(r"steps:\s*([\d,]+)", usage)
    resources["steps"] = int(m.group(1).replace(",", "")) if m else None
    for builtin in ("range_check", "poseidon", "bitwise", "pedersen"):
        m = re.search(rf"{builtin}_builtin:\s*([\d,]+)", usage)
        if m:
            resources[builtin] = int(m.group(1).replace(",", ""))
    return felts, resources


def measure(cmd: list[str], log: Path, threads: int | None = None) -> dict:
    """Runs `cmd` (stdout and stderr to `log`): exit, wall (s), the child's peak RSS in bytes
    (`ru_maxrss`: bytes on macOS, KiB on Linux). `threads` sets `RAYON_NUM_THREADS`."""
    env = {**os.environ, **({"RAYON_NUM_THREADS": str(threads)} if threads else {})}
    t0 = time.time()
    with open(log, "w") as f:
        p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, env=env)
        _, status, ru = os.wait4(p.pid, 0)
    wall = time.time() - t0
    scale = 1 if sys.platform == "darwin" else 1024
    return {"exit": os.waitstatus_to_exitcode(status), "wall_s": round(wall, 2),
            "maxrss_bytes": ru.ru_maxrss * scale}


def gib(n: int | None) -> str:
    return "?" if n is None else f"{n / 2**30:.2f}"


def prove_case(case: str, runs: int, out: Path, steps_only: bool, params: Path = PARAMS,
               threads: int | None = None) -> dict:
    scenario, ticks = case.split(":")
    ticks = int(ticks)
    fixture, _ = scarb_execute("fixture", [SCENARIOS[scenario]], out / f"{scenario}.fixture-args.json")
    # The output segment holds the returned array's length, then its felts.
    assert fixture[0] == len(fixture) - 1, "fixture: the returned array"
    args = [*fixture[1:], ticks]
    label = f"{scenario}-{ticks}"
    args_path = out / f"{label}.args.json"
    header, resources = scarb_execute("segment", args, args_path)
    # The returned array: [len, IN_HASH, CONTENT_HASH, rules, ticks, OUT_HASH, clock, defeated].
    entry = {"case": case, "scenario": scenario, "ticks": ticks, "args_felts": len(args),
             "execute": resources, "public_output": hexes(header), "runs": []}
    print(f"{label}: scarb execute steps={resources['steps']} {resources['raw']}", flush=True)
    if steps_only:
        return entry
    for run in range(1, runs + 1):
        proof = out / f"{label}.run{run}.proof.bin"
        log = out / f"{label}.run{run}.log"
        if proof.exists():
            proof.unlink()
        cmd = [str(BIN / "run_and_prove"), "--program", str(TARGET / "segment.executable.json"),
               "--program_type", "executable", "--program_arguments_file", str(args_path),
               "--params_json", str(params), "--proof_path", str(proof),
               "--proof-format", "binary", "--verify"]
        m = measure(cmd, log, threads)
        text = log.read_text(errors="replace")
        steps = [int(s) for s in STEPS_RE.findall(text)]
        r = {"run": run, **m, "prover_steps": steps[-1] if steps else None,
             "proof_bytes": proof.stat().st_size if proof.exists() else None}
        if SMALL_TRACE_LIMIT in text:
            r["result"] = "a component over 2^20 rows (canonical_small)"
        elif m["exit"] != 0 or not proof.exists():
            r["result"] = f"run_and_prove exit {m['exit']}: " + " ".join(text[-400:].split())
        else:
            r["proof_sha256"] = hashlib.sha256(proof.read_bytes()).hexdigest()
            t = time.time()
            v = subprocess.run([str(BIN / "verify"), "--proof_path", str(proof),
                                "--proof_format", "binary"], capture_output=True, text=True)
            r["verify_wall_s"] = round(time.time() - t, 2)
            claim = next((json.loads(line.split(" ", 1)[1]) for line in v.stdout.splitlines()
                          if line.startswith("VERIFICATION_OUTPUT ")), None)
            output = [int(x, 0) if isinstance(x, str) else int(x) for x in claim["output"]] if claim else None
            r["program_hash"] = claim["program_hash"] if claim else None
            same = output is not None and [o % P for o in output] == header
            r["result"] = ("verified, output = header" if v.returncode == 0 and same else
                           f"verify exit {v.returncode}, output equal: {same}")
        entry["runs"].append(r)
        print(f"  run {run}: {r['result']} wall={r['wall_s']}s maxrss={gib(r['maxrss_bytes'])}GiB "
              f"steps={r['prover_steps']} proof={r['proof_bytes']}B", flush=True)
    return entry


def table(results: list[dict]) -> str:
    lines = ["| case | steps (scarb execute) | range_check | poseidon | run | wall s | peak RSS GiB "
             "| proof bytes | verify s | result |", "|---|--:|--:|--:|--:|--:|--:|--:|--:|---|"]
    for e in results:
        x = e["execute"]
        for r in e["runs"] or [{}]:
            lines.append(
                f"| {e['case']} | {x['steps']} | {x.get('range_check', '')} | {x.get('poseidon', '')} "
                f"| {r.get('run', '')} | {r.get('wall_s', '')} | {gib(r.get('maxrss_bytes'))} "
                f"| {r.get('proof_bytes', '')} | {r.get('verify_wall_s', '')} | {r.get('result', 'not proved')} |")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--case", action="append", required=True, help="<scenario>:<ticks>")
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--out", type=Path, default=HERE / "out" / "run")
    ap.add_argument("--steps-only", action="store_true", help="scarb execute alone, no proof")
    ap.add_argument("--params", type=Path, default=PARAMS,
                    help="prover parameters (default canonical_small; params.canonical_without_pedersen.json "
                         "for a trace over canonical_small's 2^20 rows)")
    ap.add_argument("--threads", type=int, default=None,
                    help="RAYON_NUM_THREADS for run_and_prove (default: every core)")
    a = ap.parse_args()
    params = a.params.resolve()
    a.out.mkdir(parents=True, exist_ok=True)
    write_exec()
    machine = {"platform": platform.platform(), "machine": platform.machine(),
               "cpus": os.cpu_count(),
               "memory_gib": round(os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 2**30, 1)}
    print(f"machine: {machine}", flush=True)
    results = []
    for case in a.case:
        results.append(prove_case(case, a.runs, a.out, a.steps_only, params, a.threads))
        (a.out / "results.json").write_text(json.dumps(
            {"machine": machine, "params": params.name, "threads": a.threads, "results": results},
            indent=1))
    text = (f"machine: {machine}\nparams: {params.name}\nthreads: {a.threads or 'all'}\n\n"
            f"{table(results)}\n")
    (a.out / "results.txt").write_text(text)
    print("\n" + text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
