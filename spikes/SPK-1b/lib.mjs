// SPK-1b: copied from spikes/SPK-1/lib.mjs, its safety unchanged. Added: the redaction of the
// burner keys (`redactAlso`), the global budget (`budget`), the deploy-account sender and the full
// invocation tree in the trace.
// SPK-1: what every script shares. The Sepolia account comes as four variables, used by name
// only (OPERATIONS §7): STARKNET_NETWORK, STARKNET_RPC_URL, STARKNET_ACCOUNT_ADDRESS,
// STARKNET_PRIVATE_KEY. No value is ever printed. Nothing is read from the environment when this
// module is imported: a sending script first runs its repeat-run guard (`guardOutput`), then
// `configure()`, which validates the variables with errors that never contain a value, and only
// then installs the redaction (`safe`, on every console output and every error) and the provider.
import { closeSync, existsSync, openSync, renameSync, writeSync } from "node:fs";
import { join } from "node:path";
import { Account, RpcProvider, shortString } from "starknet";

const NAMES = ["STARKNET_NETWORK", "STARKNET_RPC_URL", "STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY"];
const FELT = /^0x[0-9a-fA-F]{1,64}$/;
export const USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) grimworld-spk1b/0.1";
let URL = null;
let ADDRESS = null;
let KEY = null;
let PATTERNS = [];
export let provider = null;

/** Stops with a message naming the variable and the rule, never its value. */
function refuse(message, code = 2) {
  process.stderr.write(`${message}\n`);
  process.exit(code);
}

/** Validates the four variables without echoing any of them, then installs the redaction. */
export function configure() {
  for (const name of NAMES) {
    if (!process.env[name]) refuse(`${name} is not set: launch with --with-sepolia; nothing is sent`);
  }
  for (const name of ["STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY"]) {
    if (!FELT.test(process.env[name])) {
      refuse(`${name} is not a 0x-prefixed hex felt (value not shown); nothing is sent`);
    }
  }
  let host = null;
  try {
    const parsed = new globalThis.URL(process.env.STARKNET_RPC_URL);
    if (parsed.protocol === "http:" || parsed.protocol === "https:") host = parsed.host;
  } catch {
    host = null;
  }
  if (!host) refuse("STARKNET_RPC_URL is not an http(s) URL (value not shown); nothing is sent");
  URL = process.env.STARKNET_RPC_URL;
  ADDRESS = process.env.STARKNET_ACCOUNT_ADDRESS;
  KEY = process.env.STARKNET_PRIVATE_KEY;
  PATTERNS = [
    [new RegExp(escape(URL), "g"), "<STARKNET_RPC_URL>"],
    [new RegExp(escape(host), "gi"), "<RPC_HOST>"],
    ...forms(ADDRESS).map((f) => [new RegExp(f, "gi"), "<ACCOUNT>"]),
    ...forms(KEY).map((f) => [new RegExp(f, "gi"), "<KEY>"]),
  ];
  for (const level of ["log", "info", "warn", "error", "debug"]) {
    const original = console[level].bind(console);
    console[level] = (...args) => original(...args.map((a) => safe(a)));
  }
  process.on("uncaughtException", (error) => {
    process.stderr.write(`${safe(error)}\n`);
    process.exit(1);
  });
  process.on("unhandledRejection", (error) => {
    process.stderr.write(`${safe(error)}\n`);
    process.exit(1);
  });
  provider = new RpcProvider({ nodeUrl: URL, headers: { "User-Agent": USER_AGENT } });
}

// ---------------------------------------------------------------------------------------------
// Redaction

function escape(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function forms(value) {
  // A felt as hex with or without leading zeros, and in decimal (validated by `configure`)
  const n = BigInt(value);
  return [`0x0*${n.toString(16)}`, n.toString(10)];
}

export function safe(value) {
  let text = typeof value === "string" ? value : value instanceof Error ? `${value.stack}` : JSON.stringify(value);
  for (const [pattern, placeholder] of PATTERNS) text = text.replace(pattern, placeholder);
  return text;
}

// ---------------------------------------------------------------------------------------------
// Output: each sending script writes its own output file, created exclusively

let OUT = null;

/**
 * The repeat-run guard, run before `configure()` and before any network call. A script's output
 * file exists as soon as a run has started, complete or not; then the script refuses. With
 * `--recover-incomplete`, the existing file is kept as evidence (renamed with a timestamp) and a
 * new run may start. Returns the path, which `openOutput` creates exclusively.
 */
export function guardOutput(dir, name) {
  const path = join(dir, name);
  if (existsSync(path)) {
    if (!process.argv.includes("--recover-incomplete")) {
      refuse(`${name} exists: a run has already started (complete or not); nothing is sent. ` +
        "After an incomplete run, pass --recover-incomplete to keep the file (renamed) and start again", 4);
    }
    const kept = `${path}.incomplete-${new Date().toISOString().replace(/[:.]/g, "-")}`;
    renameSync(path, kept);
    process.stderr.write(`--recover-incomplete: ${name} kept as ${kept}\n`);
  }
  return path;
}

/** Creates the output file exclusively: fails if another run created it meanwhile. */
export function openOutput(path) {
  OUT = openSync(path, "wx");
  process.on("exit", () => closeSync(OUT));
}

/** One JSON line, redacted: to the output file when one is open, to stdout otherwise. */
export function emit(record) {
  const line = `${safe(JSON.stringify(record, (_, v) => (typeof v === "bigint" ? v.toString() : v)))}\n`;
  if (OUT !== null) writeSync(OUT, line);
  else process.stdout.write(line);
}

// ---------------------------------------------------------------------------------------------
// The endpoint: a usual User-Agent on every request (the endpoint refuses requests without one)

let id = 0;
/** A raw JSON-RPC call; returns { result } or { error }. */
export async function rpcRaw(method, params = []) {
  const response = await fetch(URL, {
    method: "POST",
    headers: { "content-type": "application/json", "user-agent": USER_AGENT },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
  });
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(safe(`${method}: HTTP ${response.status} ${text.slice(0, 300)}`));
  }
}

export async function rpc(method, params = []) {
  const answer = await rpcRaw(method, params);
  if (answer.error) throw new Error(safe(`${method}: ${JSON.stringify(answer.error)}`));
  return answer.result;
}

/** Stops the process unless the endpoint is Sepolia. Every sending script calls it first. */
export async function requireSepolia() {
  const chain = await rpc("starknet_chainId");
  const name = shortString.decodeShortString(chain);
  if (name !== "SN_SEPOLIA") {
    console.error(`chain id is ${name}, not SN_SEPOLIA: nothing is sent`);
    process.exit(3);
  }
  return name;
}

export function account() {
  return new Account({ provider, address: ADDRESS, signer: KEY });
}

/** The account address, for calldata only: never print it (emit and console redact it). */
export function accountAddress() {
  return ADDRESS;
}

// ---------------------------------------------------------------------------------------------
// Money of the account (the owner's test STRK)

export const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

export async function strkBalance() {
  const [low, high] = await rpc("starknet_call", {
    request: {
      contract_address: STRK,
      entry_point_selector: "0x2e4263afad30923c891518314c3c95dbe830a16874e8abc5777a9a20b54c76e", // balanceOf
      calldata: [ADDRESS],
    },
    block_id: "latest",
  });
  return BigInt(low) + (BigInt(high) << 128n);
}

export function strk(fri) {
  return Number(fri) / 1e18;
}

/** Sierra and compiler versions from the head of a class's `sierra_program` (as SPK-2). */
export async function versions(classHash) {
  const cls = await rpc("starknet_getClass", { block_id: "latest", class_hash: classHash });
  if (!cls.sierra_program) return { sierra: null, compiler: null, cairo0: true };
  const head = cls.sierra_program.slice(0, 6).map((x) => Number(BigInt(x)));
  return { sierra: head.slice(0, 3).join("."), compiler: head.slice(3, 6).join(".") };
}

export function now() {
  return new Date().toISOString();
}

// ---------------------------------------------------------------------------------------------
// Sending and timing

/** Receipts are polled at this fixed interval (from the submission, on a fixed schedule). */
export const POLL_MS = 250;
const TIMEOUT_MS = 300_000;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * A sender with its own nonce, a hard cap on the number of transactions, and the tip the
 * provider recommends (starknet.js's default, as the MVP's client would send). `send` estimates
 * (not timed), signs and submits (the clock starts just before the submission), then polls the
 * receipt every POLL_MS until ACCEPTED_ON_L2, and returns the record. Any revert stops the run.
 */
export async function makeSender(acc, maxTx) {
  let nonce = BigInt(await acc.getNonce("latest"));
  const tip = (await provider.getEstimateTip("latest", { maxBlocks: 20 })).recommendedTip;
  let sent = 0;
  async function send(label, calls, { measured = false, trace = false } = {}) {
    if (sent >= maxTx) throw new Error(`transaction cap reached (${maxTx}): stopping before ${label}`);
    const estimate = await acc.estimateInvokeFee(calls, { nonce, tip });
    const submittedAt = now();
    const t0 = performance.now();
    const { transaction_hash: tx } = await acc.execute(calls, {
      nonce,
      tip,
      resourceBounds: estimate.resourceBounds,
    });
    const acked = performance.now() - t0;
    sent += 1;
    nonce += 1n;
    const timing = await poll(tx, t0);
    const record = await describe(tx, { trace });
    record.label = label;
    record.measured = measured;
    record.submitted_at = submittedAt;
    record.latency_ms = { submit_ack: Math.round(acked), ...timing };
    record.estimate = { overall_fee: estimate.overall_fee, resource_bounds: estimate.resourceBounds };
    emit(record);
    if (record.status !== "SUCCEEDED") throw new Error(`${label} reverted: stopping`);
    return record;
  }
  return { send, count: () => sent, tip };
}

/**
 * Polls the receipt on a fixed schedule from t0. `pre_confirmed` and `accepted` are the arrival
 * times (ms from t0) of the first receipt response that showed each status: the latency of the
 * first positive receipt response, as the client sees it. Fix loop 1: the run of 2026-09-28 also
 * recorded `*_after`, the arrival of the previous (negative) response. That is NOT a lower bound,
 * because the RPC evaluated the status at some unknown moment inside that request. So every poll
 * is now recorded as [request start, response arrival, status], to bound later runs properly: the
 * status became true after the last negative request's START and before the first positive
 * response's ARRIVAL.
 */
async function poll(tx, t0) {
  const out = { poll_ms: POLL_MS, polls: [] };
  for (let k = 1; ; k += 1) {
    const wait = t0 + k * POLL_MS - performance.now();
    if (wait > 0) await sleep(wait);
    const start = performance.now() - t0;
    const answer = await rpcRaw("starknet_getTransactionReceipt", { transaction_hash: tx });
    const at = performance.now() - t0;
    if (answer.error && answer.error.code !== 29) throw new Error(safe(JSON.stringify(answer.error)));
    const status = answer.result?.finality_status ?? "NOT_FOUND";
    out.polls.push([Math.round(start), Math.round(at), status]);
    if (status === "PRE_CONFIRMED" && out.pre_confirmed === undefined) out.pre_confirmed = Math.round(at);
    if (status === "ACCEPTED_ON_L2") {
      if (out.pre_confirmed === undefined) out.pre_confirmed_missed = true;
      out.accepted = Math.round(at);
      return out;
    }
    if (at > TIMEOUT_MS) throw new Error(`${tx}: not accepted after ${TIMEOUT_MS} ms`);
  }
}

function l2(invocation) {
  return invocation?.execution_resources?.l2_gas ?? null;
}

/** The receipt, the transaction as signed, its block's prices, and optionally the trace. */
export async function describe(tx, { trace = false } = {}) {
  const receipt = await rpc("starknet_getTransactionReceipt", { transaction_hash: tx });
  const signed = await rpc("starknet_getTransactionByHash", { transaction_hash: tx });
  const block = await rpc("starknet_getBlockWithTxHashes", { block_id: { block_number: receipt.block_number } });
  const r = receipt.execution_resources;
  const record = {
    tx,
    type: signed.type,
    status: receipt.execution_status,
    revert_reason: receipt.revert_reason ?? null,
    finality: receipt.finality_status,
    block_number: receipt.block_number,
    block_timestamp: new Date(block.timestamp * 1000).toISOString(),
    starknet_version: block.starknet_version,
    l2_gas: r.l2_gas,
    l1_data_gas: r.l1_data_gas,
    l1_gas: r.l1_gas,
    fee: BigInt(receipt.actual_fee.amount),
    fee_unit: receipt.actual_fee.unit,
    resource_bounds: signed.resource_bounds,
    tip: signed.tip,
    block_l2_gas_fri: BigInt(block.l2_gas_price.price_in_fri),
    block_l1_data_gas_fri: BigInt(block.l1_data_gas_price.price_in_fri),
    block_l1_gas_fri: BigInt(block.l1_gas_price.price_in_fri),
    events: receipt.events.length,
    event_list: receipt.events.map((e) => ({ from: e.from_address, keys: e.keys, data: e.data })),
  };
  if (trace) {
    const t = await rpc("starknet_traceTransaction", { transaction_hash: tx });
    const execute = t.execute_invocation ?? {};
    record.trace = {
      validate: l2(t.validate_invocation),
      execute_total: l2(execute),
      game_calls: (execute.calls ?? []).map((c) => ({
        to: c.contract_address,
        selector: c.entry_point_selector,
        l2_gas: l2(c),
        inner: (c.calls ?? []).map((i) => ({ to: i.contract_address, selector: i.entry_point_selector, l2_gas: l2(i) })),
      })),
      fee_transfer: l2(t.fee_transfer_invocation),
      trace_resources: t.execution_resources,
      raw_execute: execute.execution_resources,
      raw_validate: t.validate_invocation?.execution_resources,
    };
  }
  return record;
}
