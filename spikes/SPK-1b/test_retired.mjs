// SPK-1b is closed: every path that could send refuses before any network access (re-audit of PR 51,
// finding 1). Offline: fetch is replaced by a stub that counts calls; no credential is needed.
//   env -i PATH=/usr/bin:/bin HOME=$HOME node spikes/SPK-1b/test_retired.mjs
let fetches = 0;
globalThis.fetch = async () => { fetches += 1; throw new Error("the stub network was reached"); };
const lib = await import("./lib.mjs");
let failed = 0;
function check(name, ok) { console.log(`${ok ? "ok  " : "FAIL"} ${name}`); if (!ok) failed += 1; }
async function refuses(name, f) {
  let message = "";
  try { await f(); } catch (error) { message = String(error.message); }
  check(`${name} refuses`, message.startsWith(lib.RETIRED));
}
await refuses("makeSender", () => lib.makeSender({}, 1, {}, { payer: "owner" }));
await refuses("tracked", () => lib.tracked({ reserve: () => 0 }, { label: "x", payer: "owner", submit: async () => ({}) }));
await refuses("account", () => lib.account());
for (const m of ["starknet_addInvokeTransaction", "starknet_addDeclareTransaction", "starknet_addDeployAccountTransaction"]) {
  await refuses(`rpcRaw ${m}`, () => lib.rpcRaw(m, []));
}
check("no network call was made", fetches === 0);
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
