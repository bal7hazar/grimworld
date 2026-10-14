// The public endpoint probe (CLI-11e1): `pnpm --filter @grimworld/app probe:sepolia <url>…`.
// For each keyless Sepolia endpoint named, it reports the chain id, the spec version, the class
// hash at each of the four addresses of `src/chain/networks.ts` against the recorded one, and
// whether the endpoint serves `starknet_traceTransaction`, tried on one of OPS-02's transactions.
// It reads only: no transaction, no fee, no account. It reaches the internet, so it is in neither
// the default `test` nor CI.
//
// The record holds no transaction hash, so the probe finds one on the chain (or takes one with
// `--tx <hash>`, for an endpoint that cannot search): the Registry's
// deployment block by bisection on `starknet_getClassHashAt` at a block number, then, in that
// block's receipts, the transaction whose events name the Registry: its deployment.
//
// A URL with user information or a query string is refused unprinted: a keyed endpoint carries its
// key there, and only keyless ones are probed. Lines print the endpoint's origin and path only.

import { CONTRACT_NAMES, SEPOLIA } from "./src/chain/networks.ts";

const TIMEOUT_MS = 20_000;

function endpointOf(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return { refused: "not a URL" };
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return { refused: "not a URL" };
  if (url.username !== "" || url.password !== "" || value.includes("@")) {
    return { refused: "user information (a keyed endpoint is out)" };
  }
  if (url.search !== "" || url.hash !== "") return { refused: "a query string (a keyed endpoint is out)" };
  return { url: value, shown: `${url.origin}${url.pathname}`, https: url.protocol === "https:" };
}

function rpcOf(url) {
  let id = 0;
  return async (method, params) => {
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const text = await response.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      throw new Error(`HTTP ${response.status}, not JSON`);
    }
    if (body.error !== undefined) {
      const error = new Error(`${body.error.code ?? "?"} ${body.error.message ?? "error"}`);
      error.code = body.error.code;
      throw error;
    }
    return body.result;
  };
}

const said = (error) => (error instanceof Error ? error.message : String(error)).slice(0, 160);

async function attempt(run) {
  try {
    return { ok: true, value: await run() };
  } catch (error) {
    return { ok: false, error: said(error) };
  }
}

/** The chain id as text when it is a short string (`0x534e5f…` → `SN_SEPOLIA`). */
function chainName(hex) {
  let n = BigInt(hex);
  let text = "";
  while (n > 0n) {
    text = String.fromCharCode(Number(n & 0xffn)) + text;
    n >>= 8n;
  }
  return /^[\x20-\x7e]+$/.test(text) ? text : hex;
}

/** The first block at which `address` has a class, by bisection; undefined if the node cannot say. */
async function deployedAt(rpc, address, latest) {
  const at = async (block_number) => {
    try {
      await rpc("starknet_getClassHashAt", { block_id: { block_number }, contract_address: address });
      return true;
    } catch (error) {
      if (error.code === 20) return false; // CONTRACT_NOT_FOUND
      throw error;
    }
  };
  let low = 0;
  let high = latest;
  if (!(await at(high))) return undefined;
  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    if (await at(mid)) high = mid;
    else low = mid + 1;
  }
  return low;
}

async function traced(rpc, hash, source) {
  console.log(`  OPS-02 transaction (${source}): ${hash}`);
  const trace = await attempt(() => rpc("starknet_traceTransaction", { transaction_hash: hash }));
  console.log(
    `  traceTransaction: ${trace.ok ? `served (${trace.value?.type ?? "trace"})` : `not served: ${trace.error}`}`,
  );
}

async function probe(value, knownTx) {
  const endpoint = endpointOf(value);
  if (endpoint.refused) {
    console.log(`- refused unprobed: ${endpoint.refused}`);
    return;
  }
  const rpc = rpcOf(endpoint.url);
  console.log(`- ${endpoint.shown} (${endpoint.https ? "https" : "http"})`);
  const chain = await attempt(() => rpc("starknet_chainId", []));
  console.log(`  chain id: ${chain.ok ? chainName(chain.value) : `error: ${chain.error}`}`);
  const spec = await attempt(() => rpc("starknet_specVersion", []));
  console.log(`  spec version: ${spec.ok ? spec.value : `error: ${spec.error}`}`);
  let matched = 0;
  for (const name of CONTRACT_NAMES) {
    const { address, classHash } = SEPOLIA.contracts[name];
    const found = await attempt(() =>
      rpc("starknet_getClassHashAt", { block_id: "latest", contract_address: address }),
    );
    const verdict = !found.ok
      ? `error: ${found.error}`
      : BigInt(found.value) === BigInt(classHash)
        ? "matches the record"
        : `differs: ${found.value}`;
    if (found.ok && BigInt(found.value) === BigInt(classHash)) matched += 1;
    console.log(`  ${name}: ${verdict}`);
  }
  console.log(`  class hashes: ${matched}/${CONTRACT_NAMES.length} match`);

  if (knownTx !== undefined) {
    await traced(rpc, knownTx, "given by --tx");
    return;
  }
  const latest = await attempt(() => rpc("starknet_blockNumber", []));
  if (!latest.ok) {
    console.log(`  traceTransaction: not tried (blockNumber: ${latest.error})`);
    return;
  }
  const registry = SEPOLIA.contracts.registry.address;
  const deployed = await attempt(() => deployedAt(rpc, registry, latest.value));
  if (!deployed.ok || deployed.value === undefined) {
    console.log(`  traceTransaction: not tried (deployment block: ${deployed.error ?? "not found"})`);
    return;
  }
  // The deployment's own transaction: the one whose receipt emits an event naming the Registry
  // (the Universal Deployer's `ContractDeployed` carries the address in its data)
  const block = await attempt(() =>
    rpc("starknet_getBlockWithReceipts", { block_id: { block_number: deployed.value } }),
  );
  const wanted = BigInt(registry);
  const names = (felt) => {
    try {
      return BigInt(felt) === wanted;
    } catch {
      return false;
    }
  };
  const hash = block.ok
    ? block.value?.transactions?.find(({ receipt }) =>
        receipt?.events?.some((e) => names(e.from_address) || e.data?.some(names)),
      )?.receipt?.transaction_hash
    : undefined;
  if (hash === undefined) {
    console.log(`  traceTransaction: not tried (no deployment transaction: ${block.error ?? "none found"})`);
    return;
  }
  await traced(rpc, hash, `Registry deployed at block ${deployed.value}`);
}

const args = process.argv.slice(2);
const tx = args.indexOf("--tx");
const knownTx = tx === -1 ? undefined : args[tx + 1];
const urls = tx === -1 ? args : args.filter((_, i) => i !== tx && i !== tx + 1);
if (urls.length === 0 || (tx !== -1 && !/^0x[0-9a-fA-F]{1,64}$/.test(knownTx ?? ""))) {
  console.error("usage: pnpm --filter @grimworld/app probe:sepolia [--tx <OPS-02 tx hash>] <endpoint url>…");
  process.exit(2);
}
console.log(`Sepolia probe: the record ${SEPOLIA.record} (commit ${SEPOLIA.commit.slice(0, 7)})`);
for (const url of urls) await probe(url, knownTx);
