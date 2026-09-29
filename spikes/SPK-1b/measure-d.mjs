// SPK-1b, the rest of D and the clean-up (9 transactions). RETIRED: SPK-1b is closed (audit of PR 51). The measurement is done; its outputs
// are committed (measure-d-output.txt, ledger.jsonl) and its code is in the history
// (`git show 04d7ae2:spikes/SPK-1b/measure-d.mjs`). This file only refuses: nothing here can send.
import { refuseRetired } from "./lib.mjs";

refuseRetired();
