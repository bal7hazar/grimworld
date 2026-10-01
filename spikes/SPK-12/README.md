# SPK-12 — Client-side proving against L2 batches

A spike (D-161 §3, D-172 §3): nothing here merges into the contracts or the client. The analysis,
the figures and the recommendation are in
[docs/research/SPK-12-client-proving.md](../../docs/research/SPK-12-client-proving.md); this folder
holds what produced them.

| Path | What |
|---|---|
| `src/segment.cairo` | The proved program: a deterministic segment of world ticks from the stored words to the stored words (as `TickLibrary.run`), rules `Idle` or `Busy`, public output a binding header `[IN_HASH, CONTENT_HASH, rules, ticks, OUT_HASH, clock, defeated]`; `fixture` prints CBT-02's scenarios as `segment`'s arguments |
| `src/fixtures.cairo` | CBT-02's benchmark states and `Busy` rules, copied from `contracts/logic/tests/test_tick.cairo` at 2a8304d (main at e9b8cef) |
| `tests/test_segment.cairo` | Segments chain by their hashes (two halves give the whole), busy ends at the defeat, unknown rules refused, and the L2 gas of the runs `prove.py` counts in steps |
| `prove/setup.sh` | stwo-cairo at `467d5c6` with slingfall's two patches (copied verbatim from `github.com/bal7hazar/slingfall` at `d401cf2`, unchanged at `f8810c5`), built in the ignored `prove/vendor/` |
| `prove/prove.py` | Writes and builds the executables' package (`prove/out/exec/`, ignored: an executable needs `enable-gas = false`, which `snforge test` refuses), runs `scarb execute` for the steps, proves with `run_and_prove` (`canonical_small`, binary, `--verify`), checks with `verify` |
| `prove-output-*.txt` | The proving runs' tables, as printed (never a proof file) |
| `cost.py`, `cost-output.txt` | The cost model, batches against one proof a segment |
| `snforge-test-output-*.txt` | Two clean runs of the tests |

## Reproduce

```sh
scarb --manifest-path spikes/SPK-12/Scarb.toml build
(cd spikes/SPK-12 && snforge test)
spikes/SPK-12/prove/setup.sh --native            # ~50 min cold on the Mac
python3 spikes/SPK-12/prove/prove.py --runs 2 --out spikes/SPK-12/prove/out/run \
  --case representative:1 --case worst:1 --case representative:10 --case busy:10
python3 spikes/SPK-12/cost.py
```
