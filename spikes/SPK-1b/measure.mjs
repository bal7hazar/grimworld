// SPK-1b: the fixed part of a transaction with the MVP's kind of account, on Sepolia, on SPK-1's
// deployed contracts (spikes/SPK-1/sepolia.json; nothing of the game is declared again). The same
// cheap action as SPK-1: enter then leave, alternating, adventurer 3 at location 10. Planned, at
// most 44 transactions:
//   A. the reference: the owner's account (Braavos), as in SPK-1                           10
//   -  the owner funds the burner and gives it adventurer 3 (one multicall)                  1
//   -  the burner's DEPLOY_ACCOUNT (OpenZeppelin AccountUpgradeable v3.0.0, declared)        1
//   B. the burner, direct                                                                  10
//   C. the burner through a relayer of our own: the burner signs a SNIP-9 outside
//      execution, the owner's account calls execute_from_outside_v2 on it and pays          10
//   D. the burner through AVNU's public SNIP-29 paymaster (no account, no key; default fee
//      mode: the burner pays the paymaster in STRK inside its outside execution)            10
//   -  the owner takes adventurer 3 back; the burner returns what is left of its STRK        2
// Every trace is recorded. Every transaction is sent after the previous one is accepted on L2.
// The brief's caps hold over every script: ledger.jsonl counts the transactions and fees sent;
// `makeBudget` refuses past 60 transactions or 40 STRK.
//   node spikes/SPK-1b/measure.mjs          (writes measure-output.txt itself; no redirection)
// The burner's private key is generated here into burners.secret.json (ignored by git, mode 0600),
// never printed: the redaction covers it from the moment it exists.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Account, PaymasterRpc, ec, encode, hash, outsideExecution } from "starknet";
import {
  account, accountAddress, configure, describe, emit, guardOutput, makeBudget, makeSender, maxFee, now,
  openOutput, poll, POLL_MS, provider, redactAlso, requireSepolia, rpc, STRK, strk, USER_AGENT,
} from "./lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUTPUT = guardOutput(process.env.SPK1B_OUT_DIR || HERE, "measure-output.txt");
configure();

// The burner's key: generated once, kept in an ignored file, redacted from every output
const SECRETS = join(HERE, "burners.secret.json");
if (!existsSync(SECRETS)) {
  const key = encode.addHexPrefix(encode.buf2hex(ec.starkCurve.utils.randomPrivateKey()));
  writeFileSync(SECRETS, `${JSON.stringify({ oz: { private_key: key } })}\n`, { flag: "wx", mode: 0o600 });
}
const BURNER_KEY = JSON.parse(readFileSync(SECRETS, "utf8")).oz.private_key;
redactAlso(BURNER_KEY, "<BURNER_KEY>");
openOutput(OUTPUT);

const MAX_TX = 44;
const PAIRS = 5; // 5 × (enter + leave) = 10 transactions per case
const FUNDING = 3n * 10n ** 18n; // 3 STRK: 21 burner transactions and the AVNU fees, with room for the bounds
// OpenZeppelin Contracts for Cairo v3.0.0, AccountUpgradeable preset (Cairo 2.13.1, Sierra 1.7.0,
// SNIP-9 v2): its class hash as published in the release's docs, found declared on Sepolia
// (classes.mjs). Constructor: the public key.
const OZ_ACCOUNT = "0x01d1777db36cdd06dd62cfde77b1b6ae06412af95d57a13dc40ac77b8a702381";

const chain = await requireSepolia();
const budget = makeBudget(join(HERE, "ledger.jsonl"), { maxTx: 60, maxFri: 40n * 10n ** 18n });
const { contracts } = JSON.parse(readFileSync(join(HERE, "..", "SPK-1", "sepolia.json"), "utf8"));
const HUB = contracts.Hub.address;
const INST = contracts.Instances.address;
const OWNER = accountAddress();

const publicKey = ec.starkCurve.getStarkKey(BURNER_KEY);
const BURNER = hash.calculateContractAddressFromHash(publicKey, OZ_ACCOUNT, [publicKey], 0);
const paymaster = new PaymasterRpc({ nodeUrl: "https://sepolia.paymaster.avnu.fi", headers: { "User-Agent": USER_AGENT } });
const burner = new Account({ provider, address: BURNER, signer: BURNER_KEY, paymaster });
const owner = account();

async function balanceOf(address) {
  const [low, high] = await rpc("starknet_call", {
    request: { contract_address: STRK, entry_point_selector: hash.getSelectorFromName("balanceOf"), calldata: [address] },
    block_id: "latest",
  });
  return BigInt(low) + (BigInt(high) << 128n);
}

const ownerBefore = await balanceOf(OWNER);
emit({ step: "start", at: now(), chain, poll_ms: POLL_MS, strk_balance: strk(ownerBefore), max_tx: MAX_TX,
  ledger_before: budget.totals(), burner: BURNER, burner_class: OZ_ACCOUNT });

let sent = 0;
const ownerSender = await makeSender(owner, MAX_TX, budget);
const call = (contractAddress, entrypoint, calldata) => [{ contractAddress, entrypoint, calldata }];
const ENTER = call(HUB, "enter", ["3", "10"]);
const LEAVE = (instance) => call(INST, "leave", [instance]);

function opened(record) {
  const event = record.event_list.find((e) => BigInt(e.from) === BigInt(INST) && e.keys.length === 2);
  if (!event) throw new Error(`${record.label}: no Opened event`);
  return BigInt(event.keys[1]).toString();
}

/** One case: PAIRS × (enter, leave), each sent by `send(label, calls)`, traced. */
async function run(name, send) {
  for (let i = 0; i < PAIRS; i += 1) {
    const entered = await send(`${name}: enter`, ENTER);
    await send(`${name}: leave`, LEAVE(opened(entered)));
  }
}

/** Sends a transaction whose hash we get from elsewhere (deploy, AVNU), then times and records it as `makeSender` does. */
async function record(label, submit, extra = {}) {
  if (ownerSender.count() + sent >= MAX_TX) throw new Error(`transaction cap reached (${MAX_TX}): stopping before ${label}`);
  const submittedAt = now();
  const t0 = performance.now();
  const tx = await submit();
  const acked = performance.now() - t0;
  sent += 1;
  const timing = await poll(tx, t0);
  const r = await describe(tx, { trace: true });
  Object.assign(r, { label, measured: true, submitted_at: submittedAt, latency_ms: { submit_ack: Math.round(acked), ...timing }, ...extra });
  budget.spend(r);
  emit(r);
  if (r.status !== "SUCCEEDED") throw new Error(`${label} reverted: stopping`);
  return r;
}

// A. The reference: the owner's account, as in SPK-1
await run("A owner", (label, calls) => ownerSender.send(label, calls, { measured: true, trace: true }));

// The owner funds the burner and gives it adventurer 3 (setup_hub rewrites hero 3 with a new owner)
await ownerSender.send("fund the burner, give it adventurer 3", [
  ...call(STRK, "transfer", [BURNER, FUNDING.toString(), "0"]),
  ...call(HUB, "setup_hub", [BURNER]),
], { trace: true });

// The burner's DEPLOY_ACCOUNT
{
  const payload = { classHash: OZ_ACCOUNT, constructorCalldata: [publicKey], addressSalt: publicKey, contractAddress: BURNER };
  const estimate = await burner.estimateAccountDeployFee(payload);
  budget.check("deploy the burner", maxFee(estimate.resourceBounds));
  await record("deploy the burner", async () =>
    (await burner.deployAccount(payload, { resourceBounds: estimate.resourceBounds })).transaction_hash);
}

// B. The burner, direct
const burnerSender = await makeSender(burner, MAX_TX, budget);
await run("B burner direct", (label, calls) => {
  if (ownerSender.count() + burnerSender.count() + sent >= MAX_TX) throw new Error(`transaction cap reached before ${label}`);
  return burnerSender.send(label, calls, { measured: true, trace: true });
});

// C. The burner through a relayer of our own: the owner's account pays
const snip9 = await burner.getSnip9Version();
emit({ step: "snip9", version: snip9 });
await run("C burner via relayer", async (label, calls) => {
  if (ownerSender.count() + burnerSender.count() + sent >= MAX_TX) throw new Error(`transaction cap reached before ${label}`);
  const seconds = Math.floor(Date.now() / 1000);
  const outside = await burner.getOutsideTransaction(
    { caller: OWNER, execute_after: seconds - 300, execute_before: seconds + 3600 }, calls, snip9);
  return ownerSender.send(label, outsideExecution.buildExecuteFromOutsideCall(outside), { measured: true, trace: true });
});

// D. The burner through AVNU's public paymaster, default fee mode in STRK (no key)
{
  const details = { feeMode: { mode: "default", gasToken: STRK } };
  await run("D burner via AVNU", async (label, calls) => {
    if (ownerSender.count() + burnerSender.count() + sent >= MAX_TX) throw new Error(`transaction cap reached before ${label}`);
    const fee = await burner.estimatePaymasterTransactionFee(calls, details);
    const bound = BigInt(fee.suggested_max_fee_in_gas_token);
    budget.check(label, bound);
    const before = await balanceOf(BURNER);
    const r = await record(label, async () =>
      (await burner.executePaymasterTransaction(calls, details, bound)).transaction_hash,
    { paymaster: { estimate: fee, max_fee_in_gas_token: bound } });
    r.paymaster.paid_by_burner_fri = before - (await balanceOf(BURNER));
    emit({ step: "paid to AVNU", label, tx: r.tx, paid_by_burner_fri: r.paymaster.paid_by_burner_fri, receipt_fee_fri: r.fee });
    return r;
  });
}

// The owner takes adventurer 3 back; the burner returns what is left of its STRK
await ownerSender.send("give adventurer 3 back to the owner", call(HUB, "setup_hub", [OWNER]));
{
  const left = await balanceOf(BURNER);
  const probe = await burner.estimateInvokeFee(call(STRK, "transfer", [OWNER, left.toString(), "0"]));
  const amount = left - 2n * maxFee(probe.resourceBounds, burnerSender.tip);
  if (amount > 0n) {
    await burnerSender.send("return the burner's STRK", call(STRK, "transfer", [OWNER, amount.toString(), "0"]));
  }
}

const ownerAfter = await balanceOf(OWNER);
emit({ step: "done", at: now(), transactions: ownerSender.count() + burnerSender.count() + sent,
  owner_balance_delta_strk: strk(ownerBefore - ownerAfter), burner_left_strk: strk(await balanceOf(BURNER)),
  ledger_after: budget.totals() });
