// SPK-1b: the rest of case D after measure.mjs stopped. On 2026-09-28 measure.mjs stopped before
// sending the second `leave` through AVNU: `paymaster_buildTransaction` simulated it as "not the
// owner", on a state that did not yet hold the `enter` accepted in the block before (the instance
// is opened by that enter). Nothing was sent for it. This script sends that `leave`, then the 3
// remaining pairs, then gives adventurer 3 back to the owner and returns the burner's STRK: 44
// transactions in total with measure.mjs's 35, as planned. It resumes from what the outputs record.
// A failed build sends nothing and is retried after 3 s, at most 10 times; a revert stops the run.
// Fix loop 1: the ledger reserves every transaction before it is submitted, and what an interrupted
// run left unresolved is reconciled before anything is sent.
//   node spikes/SPK-1b/measure-d.mjs        (writes measure-d-output.txt itself; no redirection)
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Account, PaymasterRpc, hash } from "starknet";
import {
  account, accountAddress, configure, emit, excerpt, guardOutput, makeLedger, makeSender, maxFee, now,
  openOutput, provider, receiptOrNull, redactAlso, requireSepolia, rpc, STRK, strk, tracked, USER_AGENT,
} from "./lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUTPUT = guardOutput(process.env.SPK1B_OUT_DIR || HERE, "measure-d-output.txt");
configure();
const BURNER_KEY = JSON.parse(readFileSync(join(HERE, "burners.secret.json"), "utf8")).oz.private_key;
redactAlso(BURNER_KEY, "<BURNER_KEY>");
openOutput(OUTPUT);

const chain = await requireSepolia();
const ledger = makeLedger(join(HERE, "ledger.jsonl"), { maxTx: 60, maxSpentFri: 40n * 10n ** 18n });
const { contracts } = JSON.parse(readFileSync(join(HERE, "..", "SPK-1", "sepolia.json"), "utf8"));
const HUB = contracts.Hub.address;
const INST = contracts.Instances.address;
const OWNER = accountAddress();
// What case D has sent so far: every receipt recorded by measure.mjs and by earlier runs of this
// script (their outputs are kept, renamed, by --recover-incomplete)
const records = (name) => readFileSync(join(HERE, name), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const first = records("measure-output.txt");
const earlier = readdirSync(HERE).filter((f) => f.startsWith("measure-d-output.txt.incomplete-")).sort();
const done = [first, ...earlier.map(records)].flat().filter((r) => r.label?.startsWith("D burner via AVNU") && r.event_list);
const { burner: BURNER } = first.find((r) => r.step === "start");
const lastEnter = done.at(-1).label.endsWith("enter") ? done.at(-1) : null;
const PAIRS_LEFT = 5 - done.filter((r) => r.label.endsWith("enter")).length;

const paymaster = new PaymasterRpc({ nodeUrl: "https://sepolia.paymaster.avnu.fi", headers: { "User-Agent": USER_AGENT } });
const burner = new Account({ provider, address: BURNER, signer: BURNER_KEY, paymaster });
const owner = account();

// What an interrupted run left: settled from its receipt, voided if never broadcast, or kept
const unresolved = await ledger.reconcile({
  receiptOf: receiptOrNull,
  nonceOf: (payer) => (payer === "owner" ? owner : burner).getNonce("latest"),
});
if (unresolved.length) throw new Error(`ledger: ${unresolved.length} transaction(s) still unresolved: nothing is sent`);
// The plan: 44 transactions in total, whatever earlier runs sent
const MAX_TX = 44 - ledger.totals().transactions;

async function balanceOf(address) {
  const [low, high] = await rpc("starknet_call", {
    request: { contract_address: STRK, entry_point_selector: hash.getSelectorFromName("balanceOf"), calldata: [address] },
    block_id: "latest",
  });
  return BigInt(low) + (BigInt(high) << 128n);
}

const ownerBefore = await balanceOf(OWNER);
emit({ step: "start", at: now(), chain, max_tx: MAX_TX, ledger_before: ledger.totals(), burner: BURNER });

const call = (contractAddress, entrypoint, calldata) => [{ contractAddress, entrypoint, calldata }];
function opened(record) {
  const event = record.event_list.find((e) => BigInt(e.from) === BigInt(INST) && e.keys.length === 2);
  if (!event) throw new Error(`${record.label}: no Opened event`);
  return BigInt(event.keys[1]).toString();
}

let sent = 0;
const details = { feeMode: { mode: "default", gasToken: STRK } };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function viaAvnu(label, calls) {
  if (sent >= MAX_TX) throw new Error(`transaction cap reached (${MAX_TX}): stopping before ${label}`);
  let fee = null;
  for (let attempt = 1; fee === null; attempt += 1) {
    try {
      fee = await burner.estimatePaymasterTransactionFee(calls, details);
    } catch (error) {
      emit({ step: "build refused, nothing sent", label, attempt, error: excerpt(String(error.message ?? error), 200) });
      if (attempt >= 10) throw error;
      await sleep(3000);
    }
  }
  // The paymaster quotes again inside executePaymasterTransaction; its second quote may be higher
  // than the first (the run of 2026-09-28 refused one, client-side, before signing: nothing sent)
  const bound = (BigInt(fee.suggested_max_fee_in_gas_token) * 3n) / 2n;
  const before = await balanceOf(BURNER);
  sent += 1;
  // Reserved at the most the burner may pay AVNU; settled against its net transfers in the receipt
  const r = await tracked(ledger, {
    label, payer: "burner via AVNU", payerAddress: BURNER, maxFee: bound, paymaster: true,
    extra: { paymaster: { estimate: fee, max_fee_in_gas_token: bound } },
    submit: async () => (await burner.executePaymasterTransaction(calls, details, bound)).transaction_hash,
  });
  const paid = before - (await balanceOf(BURNER));
  emit({ step: "paid to AVNU", label, tx: r.tx, paid_by_burner_fri: paid, receipt_fee_fri: r.fee });
  return r;
}

emit({ step: "case D so far", receipts: done.length, pending_leave: lastEnter?.tx ?? null, pairs_left: PAIRS_LEFT });
if (lastEnter) await viaAvnu("D burner via AVNU: leave", call(INST, "leave", [opened(lastEnter)]));
for (let i = 0; i < PAIRS_LEFT; i += 1) {
  const entered = await viaAvnu("D burner via AVNU: enter", call(HUB, "enter", ["3", "10"]));
  await viaAvnu("D burner via AVNU: leave", call(INST, "leave", [opened(entered)]));
}

// The owner takes adventurer 3 back; the burner returns what is left of its STRK
const ownerSender = await makeSender(owner, MAX_TX - sent, ledger, { payer: "owner" });
await ownerSender.send("give adventurer 3 back to the owner", call(HUB, "setup_hub", [OWNER]));
const burnerSender = await makeSender(burner, MAX_TX - sent - ownerSender.count(), ledger, { payer: "burner" });
{
  const left = await balanceOf(BURNER);
  const probe = await burner.estimateInvokeFee(call(STRK, "transfer", [OWNER, left.toString(), "0"]));
  const amount = left - 2n * maxFee(probe.resourceBounds, burnerSender.tip);
  if (amount > 0n) {
    await burnerSender.send("return the burner's STRK", call(STRK, "transfer", [OWNER, amount.toString(), "0"]));
  }
}

const ownerAfter = await balanceOf(OWNER);
emit({ step: "done", at: now(), transactions: sent + ownerSender.count() + burnerSender.count(),
  owner_balance_delta_strk: strk(ownerBefore - ownerAfter), burner_left_strk: strk(await balanceOf(BURNER)),
  ledger_after: ledger.totals() });
