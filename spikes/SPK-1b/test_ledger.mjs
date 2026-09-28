// SPK-1b fix loop 1: the ledger under faults, offline. Synthetic variables, a stubbed `fetch` in
// place of the RPC (nothing reaches any network) and a stub account whose `execute` counts the
// broadcasts. The real `makeSender`, `tracked`, `poll`, `describe` and `makeLedger` run.
//   node spikes/SPK-1b/test_ledger.mjs
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

Object.assign(process.env, {
  STARKNET_NETWORK: "sepolia",
  STARKNET_RPC_URL: "https://rpc.invalid.example/v0_10/synthetic",
  STARKNET_ACCOUNT_ADDRESS: `0x${"abc123".padStart(64, "0")}`,
  STARKNET_PRIVATE_KEY: `0x${"def456".padStart(64, "0")}`,
});
const lib = await import("./lib.mjs");
const { configure, makeLedger, makeSender, openOutput, receiptOrNull, tracked } = lib;
configure();
const DIR = mkdtempSync(join(tmpdir(), "spk1b-ledger-"));
openOutput(join(DIR, "emitted.txt"));

// ---------------------------------------------------------------------------------------------
// The stub chain: every transaction the stub account broadcasts is known here
const STRK = BigInt(lib.STRK);
const TRANSFER = "0x99cd8bde557814842a3121e8ddfd433a539b8c9f14bf31ebf108d12e6196e9";
const chain = { txs: new Map(), failReceipt: false, failTrace: false, unknown: false };
const hex = (n) => `0x${BigInt(n).toString(16)}`;
function receipt(tx) {
  const t = chain.txs.get(tx);
  return {
    transaction_hash: tx, execution_status: "SUCCEEDED", finality_status: "ACCEPTED_ON_L2", block_number: 7,
    execution_resources: { l2_gas: 1000, l1_data_gas: 10, l1_gas: 0 },
    actual_fee: { amount: hex(t.fee), unit: "FRI" }, events: t.events,
  };
}
globalThis.fetch = async (url, options) => {
  const { id, method, params } = JSON.parse(options.body);
  const answer = (result) => ({ status: 200, text: async () => JSON.stringify({ jsonrpc: "2.0", id, result }) });
  const error = (code, message) => ({ status: 200, text: async () => JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) });
  const tx = params?.transaction_hash;
  switch (method) {
    case "starknet_getTransactionReceipt":
      if (!chain.txs.has(tx) || chain.unknown) return error(29, "Transaction hash not found");
      if (chain.failReceipt) return error(-32603, "internal error while reading the receipt");
      return answer(receipt(tx));
    case "starknet_getTransactionByHash":
      return answer({ type: "INVOKE", resource_bounds: {}, tip: "0x0" });
    case "starknet_getBlockWithTxHashes":
      return answer({ timestamp: 1, starknet_version: "0.14.4", l2_gas_price: { price_in_fri: "0x1" },
        l1_data_gas_price: { price_in_fri: "0x1" }, l1_gas_price: { price_in_fri: "0x1" } });
    case "starknet_traceTransaction":
      if (chain.failTrace) return error(-32603, "internal error while tracing");
      return answer({ execution_resources: { l2_gas: 900 }, validate_invocation: null, execute_invocation: null, fee_transfer_invocation: null });
    default:
      return error(-32601, `stub: ${method} not served`);
  }
};

let broadcasts = 0;
function stubAccount({ failSubmit = false, fee = 700n, events = [] } = {}) {
  return {
    getNonce: async () => "0x5",
    estimateInvokeFee: async () => ({
      overall_fee: fee,
      resourceBounds: { l1_gas: { max_amount: "0x0", max_price_per_unit: "0x0" }, l2_gas: { max_amount: "0x64", max_price_per_unit: "0xa" },
        l1_data_gas: { max_amount: "0x0", max_price_per_unit: "0x0" } },
    }),
    execute: async () => {
      broadcasts += 1;
      if (failSubmit) throw new Error("socket hang up after the request was written");
      const tx = hex(0x1000 + broadcasts);
      chain.txs.set(tx, { fee, events });
      return { transaction_hash: tx };
    },
  };
}

let failures = 0;
function check(name, ok) {
  console.log(`${ok ? "ok  " : "FAIL"} ${name}`);
  if (!ok) failures += 1;
}
async function rejects(promise, pattern) {
  try {
    await promise;
    return false;
  } catch (error) {
    return pattern.test(String(error.message));
  }
}
/** A ledger file already holding `n` settled transactions of `fee` each. */
function ledgerWith(name, n, fee = 1n) {
  const path = join(DIR, name);
  const lines = [];
  for (let i = 1; i <= n; i += 1) {
    const id = `old#${i}`;
    lines.push({ kind: "reserve", id, label: `old ${i}`, payer: "owner", max_fee: String(fee), paymaster: false, nonce: null },
      { kind: "sent", id, tx: hex(i) }, { kind: "settle", id, tx: hex(i), fee: String(fee), spent: String(fee), how: "receipt fee" });
  }
  writeFileSync(path, lines.map((l) => `${JSON.stringify(l)}\n`).join(""));
  return path;
}
const CAPS = { maxTx: 60, maxSpentFri: 40n * 10n ** 18n };
const nonceOf = async () => 5n;

// 1. A failure after the broadcast, while polling the receipt, at 59 transactions: the broadcast is
// counted at once, and no second broadcast can follow (the auditor's fault test allowed two)
{
  const path = ledgerWith("at59.jsonl", 59);
  const ledger = makeLedger(path, CAPS);
  const sender = await makeSender(stubAccount(), 10, ledger, { payer: "owner", tip: 0n });
  chain.failReceipt = true;
  broadcasts = 0;
  check("1a the send fails after its broadcast", await rejects(sender.send("x", []), /internal error while reading the receipt/));
  const t = ledger.totals();
  check("1b the broadcast is counted: 60 transactions", t.transactions === 60);
  check("1c its hash is in the ledger, unresolved", t.unresolved.length === 1 && t.unresolved[0].tx === hex(0x1001));
  check("1d it counts at its maximum fee (100 × 10 fri)", t.spent_fri === 59n + 1000n);
  check("1e a second send is refused before any broadcast", await rejects(sender.send("y", []), /unresolved/) && broadcasts === 1);
  check("1f the hash was written before the receipt was asked for",
    readFileSync(path, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)).at(-1).kind === "sent");

  // 2. The recovery: a new run reads the same ledger; it may not send until the entry is reconciled
  const again = makeLedger(path, CAPS);
  check("2a a new run refuses to reserve while the entry is unresolved",
    await rejects(Promise.resolve().then(() => again.reserve({ label: "z", payer: "owner", maxFee: 1n })), /unresolved/));
  const still = await again.reconcile({ receiptOf: receiptOrNull, nonceOf });
  check("2b reconcile while the receipt cannot be read: still unresolved", still.length === 1);
  chain.failReceipt = false;
  const none = await again.reconcile({ receiptOf: receiptOrNull, nonceOf });
  const settled = again.entries().find((e) => e.tx === hex(0x1001));
  check("2c reconcile once the receipt is there: settled at the receipt's fee", none.length === 0 && settled.status === "settled" && settled.fee === 700n);
  check("2d the cap still holds: 60 transactions, the next is refused",
    again.totals().transactions === 60 && await rejects(Promise.resolve().then(() => again.reserve({ label: "z", payer: "owner", maxFee: 1n })), /60 transactions of 60/));
  check("2e broadcasts over the whole scenario: 1", broadcasts === 1);
}

// 3. A failure during the trace collection (after the receipt): unresolved, then reconciled
{
  const ledger = makeLedger(join(DIR, "trace.jsonl"), CAPS);
  const sender = await makeSender(stubAccount(), 10, ledger, { payer: "owner", tip: 0n });
  chain.failTrace = true;
  check("3a the send fails while collecting the trace", await rejects(sender.send("x", [], { trace: true }), /internal error while tracing/));
  check("3b unresolved with its hash", ledger.totals().unresolved.length === 1 && Boolean(ledger.totals().unresolved[0].tx));
  check("3c reconcile cannot settle while the trace fails", (await ledger.reconcile({ receiptOf: receiptOrNull, nonceOf })).length === 1);
  chain.failTrace = false;
  check("3d reconcile settles once it can", (await ledger.reconcile({ receiptOf: receiptOrNull, nonceOf })).length === 0);
}

// 4. A failure during the submission, before any hash: the payer's nonce decides
for (const [label, current, status] of [["4a nonce unchanged: void", 5n, "void"], ["4b nonce moved: kept at its maximum", 6n, "kept"]]) {
  const ledger = makeLedger(join(DIR, `submit-${status}.jsonl`), CAPS);
  const sender = await makeSender(stubAccount({ failSubmit: true }), 10, ledger, { payer: "owner", tip: 0n });
  const failed = await rejects(sender.send("x", []), /socket hang up/);
  const blocked = await rejects(Promise.resolve().then(() => ledger.reserve({ label: "y", payer: "owner", maxFee: 1n })), /unresolved/);
  await ledger.reconcile({ receiptOf: receiptOrNull, nonceOf: async () => current });
  const [entry] = ledger.entries();
  const t = ledger.totals();
  check(`${label} (blocked before reconcile, then ${status})`, failed && blocked && entry.status === status &&
    t.transactions === (status === "void" ? 0 : 1) && t.spent_fri === (status === "void" ? 0n : 1000n) && t.unresolved.length === 0);
}

// 5. A paymaster transaction: the receipt's fee (paid by the relayer) and the owner's spending (the
// burner's net transfers) are kept apart; without a transfer from the burner, the reservation stays
{
  const BURNER = `0x${"b0b".padStart(64, "0")}`;
  const FORWARDER = `0x${"f0f".padStart(64, "0")}`;
  const transfer = (from, to, amount) => ({ from_address: lib.STRK, keys: [TRANSFER, from, to], data: [hex(amount), "0x0"] });
  const ledger = makeLedger(join(DIR, "paymaster.jsonl"), { maxTx: 60, maxSpentFri: 1000n });
  const submit = (fee, events) => async () => (await stubAccount({ fee, events }).execute()).transaction_hash;
  const r = await tracked(ledger, { label: "D enter", payer: "burner via AVNU", payerAddress: BURNER, maxFee: 950n, paymaster: true,
    trace: false, submit: submit(50n, [transfer(BURNER, FORWARDER, 700n), transfer(FORWARDER, BURNER, 400n)]) });
  const e = ledger.entries().find((x) => x.tx === r.tx);
  check("5a settled: receipt fee 50 (the relayer's), spent 300 (700 sent, 400 refunded)", e.fee === 50n && e.spent === 300n);
  const t = ledger.totals();
  check("5b the totals keep them apart", t.fee_fri === 50n && t.spent_fri === 300n);
  check("5c the spending cap counts the burner's payment, not the receipt fee: 300 + 750 > 1000 is refused",
    await rejects(Promise.resolve().then(() => ledger.reserve({ label: "next", payer: "burner via AVNU", maxFee: 750n, paymaster: true })), /would pass/));
  const r2 = await tracked(ledger, { label: "D leave", payer: "burner via AVNU", payerAddress: BURNER, maxFee: 600n, paymaster: true,
    trace: false, submit: submit(40n, [transfer(FORWARDER, BURNER, 5n)]) });
  const e2 = ledger.entries().find((x) => x.tx === r2.tx);
  check("5d no transfer from the burner in the receipt: the reservation (600) is kept as the spending",
    e2.fee === 40n && e2.spent === 600n && /reservation kept/.test(e2.how));
}

// 6. The committed ledger (migrated): 44 transactions, receipt fees and the owner's spending apart
{
  const t = makeLedger(new URL("./ledger.jsonl", import.meta.url).pathname, CAPS).totals();
  check(`6 the committed ledger: 44 transactions, fees ${t.fee_strk.toFixed(4)} STRK, spent ${t.spent_strk.toFixed(4)} STRK, 0 unresolved`,
    t.transactions === 44 && t.fee_strk.toFixed(4) === "3.6938" && t.spent_strk.toFixed(4) === "3.9654" && t.unresolved.length === 0);
}

console.log(failures ? `${failures} failed` : "all passed");
process.exit(failures ? 1 : 0);
