// SPK-1 step 2: the measured actions on Sepolia, from the owner's account, on the contracts of
// sepolia.json. Same calls, instance ids and boards as SPK-2's devnet_measure.py (native, production
// form: owner checked, one felt per goblin). At most 98 transactions, planned:
//   4 queue setups + 4 queues (10 moves with 8 goblins, 5, 1, 10 exploring: gas)       8
//   20 × (setup of the capped worst-case board + the worst tick under D-127)          40
//   25 × (enter + leave), the cheap action for latency                                50
// Every transaction is sent after the previous one is accepted on L2; each receipt is polled
// every POLL_MS from its submission.
//   node spikes/SPK-1/measure.mjs          (writes measure-output.txt itself; no redirection)
// The repeat-run guard runs first, before the variables are read or the network called: if
// measure-output.txt exists (a run has started, complete or not), the script refuses. After an
// incomplete run, --recover-incomplete keeps the file (renamed with a timestamp) and starts again.
// The file is then created exclusively. SPK1_OUT_DIR moves the output (local tests of the guard).
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  account, accountAddress, configure, emit, guardOutput, makeSender, now, openOutput, POLL_MS, requireSepolia,
  strk, strkBalance,
} from "./lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUTPUT = guardOutput(process.env.SPK1_OUT_DIR || HERE, "measure-output.txt");
configure();
openOutput(OUTPUT);

const MAX_TX = 98;
const TICKS = 20;
const ENTER_LEAVE = 25;

const chain = await requireSepolia();
const { contracts } = JSON.parse(readFileSync(join(HERE, "sepolia.json"), "utf8"));
const HUB = contracts.Hub.address;
const INST = contracts.Instances.address;
const OWNER = accountAddress();
const FELT = "0";
const CHECKED = "1";

const acc = account();
const before = await strkBalance();
const { send, count, tip } = await makeSender(acc, MAX_TX);
emit({ step: "start", at: now(), chain, poll_ms: POLL_MS, tip, strk_balance: strk(before), max_tx: MAX_TX });

const call = (contractAddress, entrypoint, calldata) => [{ contractAddress, entrypoint, calldata }];
const west = (n) => [String(n), ...Array(n).fill("3")];

// 1. Queues (SPK-2's instances 18 to 21: checked, one felt per goblin)
for (const [id, goblins] of [["18", "8"], ["19", "8"], ["20", "8"], ["21", "0"]]) {
  await send(`setup queue ${id}`, call(INST, "setup_queue", [id, goblins, OWNER]));
}
for (const [label, id, n] of [
  ["queue of 10 moves, checked", "18", 10],
  ["queue of 5 moves, checked", "19", 5],
  ["queue of 1 move, checked", "20", 1],
  ["queue of 10 moves, no goblin, checked", "21", 10],
]) {
  await send(label, call(INST, "walk", [id, ...west(n), FELT, CHECKED]), { measured: true, trace: true });
}

// 2. The worst tick under D-127 (SPK-2's instance 31: capped winding board, 15 layers, 8 goblins
// reached, one felt per goblin, owner checked), on a board reset before every tick
const TICK = "capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked";
for (let i = 0; i < TICKS; i += 1) {
  await send("setup board 31", call(INST, "setup_board", ["31", OWNER]));
  await send(TICK, call(INST, "attack", ["31", "1", FELT, CHECKED]), { measured: true, trace: i === 0 });
}

// 3. Enter and leave (adventurer 3, location 10), alternating; leave takes the id `enter` opened
for (let i = 0; i < ENTER_LEAVE; i += 1) {
  const entered = await send("enter", call(HUB, "enter", ["3", "10"]), { measured: true, trace: i === 0 });
  const opened = entered.event_list.find((e) => BigInt(e.from) === BigInt(INST) && e.keys.length === 2);
  if (!opened) throw new Error("enter: no Opened event");
  const instance = BigInt(opened.keys[1]).toString();
  await send("leave", call(INST, "leave", [instance]), { measured: true, trace: i === 0 });
}

const after = await strkBalance();
emit({ step: "done", at: now(), transactions: count(), balance_delta_strk: strk(before - after), strk_balance: strk(after) });
