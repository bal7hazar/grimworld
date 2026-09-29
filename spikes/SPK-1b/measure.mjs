// SPK-1b, the run: A, the burner, B, C, and D until it stopped (35 transactions). RETIRED: SPK-1b is closed (audit of PR 51). The measurement is done; its outputs
// are committed (measure-output.txt, ledger.jsonl) and its code is in the history
// (`git show 04d7ae2:spikes/SPK-1b/measure.mjs`). This file only refuses: nothing here can send.
import { refuseRetired } from "./lib.mjs";

refuseRetired();
