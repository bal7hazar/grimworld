// SPK-1b: the redaction of a burner key, with synthetic values only (no network, nothing sent).
// `configure()` gets synthetic variables; `redactAlso` then covers a synthetic key, in hex with and
// without leading zeros, upper case, and decimal; a malformed key is refused without its value.
//   node spikes/SPK-1b/test_redaction.mjs
import { spawnSync } from "node:child_process";

const KEY = `0x${"c0ffee1234567".padStart(64, "0")}`;
const env = {
  ...process.env,
  STARKNET_NETWORK: "sepolia",
  STARKNET_RPC_URL: "https://rpc.invalid.example/v0_10/synthetic",
  STARKNET_ACCOUNT_ADDRESS: "0x0000000000000000000000000000000000000000000000000000000000abc123",
  STARKNET_PRIVATE_KEY: "0x0000000000000000000000000000000000000000000000000000000000def456",
};
const LIB = new URL("./lib.mjs", import.meta.url).href;
const n = BigInt(KEY);

function child(code) {
  return spawnSync(process.execPath, ["--input-type=module", "-e", code], { env, encoding: "utf8" });
}

let failures = 0;
function check(name, ok) {
  console.log(`${ok ? "ok  " : "FAIL"} ${name}`);
  if (!ok) failures += 1;
}

const forms = [KEY, `0x${n.toString(16)}`, `0x${n.toString(16).toUpperCase()}`, n.toString(10)];
const out = child(`
  import { configure, emit, redactAlso, safe } from ${JSON.stringify(LIB)};
  configure();
  redactAlso(${JSON.stringify(KEY)}, "<BURNER_KEY>");
  for (const f of ${JSON.stringify(forms)}) { console.log("log", f); emit({ key: f }); console.error(new Error("err " + f)); }
`);
const text = out.stdout + out.stderr;
check("the child ran", out.status === 0);
for (const f of forms) check(`form ${f.length} characters redacted`, !text.toLowerCase().includes(f.toLowerCase()));
check("the placeholder is there", (text.match(/<BURNER_KEY>/g) ?? []).length === forms.length * 3);

const bad = child(`
  import { configure, redactAlso } from ${JSON.stringify(LIB)};
  configure();
  redactAlso("not-a-felt-SECRETVALUE", "<BURNER_KEY>");
`);
check("a malformed key is refused", bad.status === 2);
check("without its value", !(bad.stdout + bad.stderr).includes("SECRETVALUE"));

// Fix loop 1: redact the whole text, then cut. Each protected value, in each of its forms, is put
// across the cut at every offset; no prefix of 4 characters or more may survive. The old order
// (cut, then redact) is run on the same inputs to show the test catches the leak.
const boundary = child(`
  import { configure, excerpt, redactAlso, rpcRaw, safe } from ${JSON.stringify(LIB)};
  configure();
  redactAlso(${JSON.stringify(KEY)}, "<BURNER_KEY>");
  const felt = (v) => { const n = BigInt(v); return [v, "0x" + n.toString(16), n.toString(10)]; };
  const values = {
    STARKNET_RPC_URL: [process.env.STARKNET_RPC_URL, new URL(process.env.STARKNET_RPC_URL).host],
    STARKNET_ACCOUNT_ADDRESS: felt(process.env.STARKNET_ACCOUNT_ADDRESS),
    STARKNET_PRIVATE_KEY: felt(process.env.STARKNET_PRIVATE_KEY),
    BURNER_KEY: felt(${JSON.stringify(KEY)}),
  };
  const result = {};
  for (const [name, forms] of Object.entries(values)) {
    let cases = 0, leaks = 0, oldLeaks = 0, rpcLeaks = 0;
    for (const v of forms) {
      for (let k = 4; k < v.length; k += 1) {
        const text = "x".repeat(200 - k) + v + " tail";
        cases += 1;
        if (excerpt(text, 200).includes(v.slice(0, k))) leaks += 1;
        if (safe(text.slice(0, 200)).includes(v.slice(0, k))) oldLeaks += 1;
        // The lib's own path: an RPC answer that is not JSON, cut at 400 in the error
        const head = "starknet_chainId: HTTP 502 ";
        globalThis.fetch = async () => ({ status: 502, text: async () => "y".repeat(400 - head.length - k) + v + " tail" });
        try { await rpcRaw("starknet_chainId"); } catch (error) { if (String(error.message).includes(v.slice(0, k))) rpcLeaks += 1; }
      }
    }
    result[name] = { cases, leaks, oldLeaks, rpcLeaks };
  }
  process.stdout.write(JSON.stringify(result));
`);
check("boundary: the child ran", boundary.status === 0);
const found = boundary.status === 0 ? JSON.parse(boundary.stdout.split("\n").at(-1)) : {};
for (const [name, r] of Object.entries(found)) {
  check(`boundary ${name}: ${r.cases} cuts, ${r.leaks} leak through excerpt, ${r.rpcLeaks} through rpcRaw ` +
    `(cut-then-redact would leak ${r.oldLeaks})`, r.leaks === 0 && r.rpcLeaks === 0 && r.oldLeaks > 0);
}
check("boundary: the four protected values were covered", Object.keys(found).length === 4);

// No script of the spike cuts an error or a text before redacting it
const { readdirSync, readFileSync } = await import("node:fs");
const here = new URL(".", import.meta.url).pathname;
const cuts = readdirSync(here).filter((f) => f.endsWith(".mjs") && !f.startsWith("test_"))
  .filter((f) => /(error|text|message)[^;\n]*\.slice\(/.test(readFileSync(here + f, "utf8")));
check(`no script cuts an error or a response before redaction (${cuts.join(", ") || "none"})`, cuts.length === 0);

console.log(failures ? `${failures} failed` : "all passed");
process.exit(failures ? 1 : 0);
