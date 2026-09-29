import { createFundingChain } from "./chain.ts";
import { ConfigError, ENV, readConfig } from "./config.ts";
import { createFunderServer, createLogger } from "./http.ts";
import { LedgerLocked, fileLedger, memoryLedger, type Ledger } from "./ledger.ts";
import { HOUR_MS, createFundingService } from "./service.ts";

/**
 * Starts the funding service from the environment (`config.ts`, `ENV`): `node src/main.ts`.
 * Prints one line of JSON per event on stdout; the first, `listening`, gives the port.
 */

let config;
try {
  config = readConfig(process.env);
} catch (error) {
  process.stderr.write(
    `funder: ${error instanceof ConfigError ? error.message : "bad configuration"}\n`,
  );
  process.exit(1);
}
// Read once, then gone from the environment: nothing started later, and no dump of the
// environment, can find it there.
delete process.env[ENV.key];

const log = createLogger((line) => process.stdout.write(`${line}\n`), config.funderKey.forms());
let ledger: Ledger;
try {
  ledger = config.stateFile ? fileLedger(config.stateFile) : memoryLedger();
} catch (error) {
  // Two services on one ledger could hand two executions the same nonce (fix loops 2 and 3).
  process.stderr.write(`funder: ${error instanceof LedgerLocked ? error.message : "no state"}\n`);
  process.exit(1);
}
// Every exit Node runs handlers for (a normal end, `process.exit`, an uncaught error) removes the
// lock; only a kill (SIGKILL, the OOM killer) or a power loss leaves it, for the operator.
process.on("exit", () => ledger.close());
const service = createFundingService({
  chain: createFundingChain(config),
  ledger,
  limits: {
    dailyBudget: config.dailyBudget,
    clientRate: config.clientRate,
    windowMs: HOUR_MS,
    settleMs: 60_000,
    pollMs: 500,
  },
  onEvent: log,
});
const server = createFunderServer({
  service,
  trustProxy: config.trustProxy,
  origin: config.origin,
  log,
});

server.listen(config.port, config.host, () => {
  const address = server.address();
  log("listening", {
    port: String(typeof address === "object" && address ? address.port : config.port),
  });
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    server.close();
    server.closeAllConnections();
    ledger.close();
    process.exit(0);
  });
}
