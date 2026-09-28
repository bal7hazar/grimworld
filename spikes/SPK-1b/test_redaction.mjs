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

console.log(failures ? `${failures} failed` : "all passed");
process.exit(failures ? 1 : 0);
