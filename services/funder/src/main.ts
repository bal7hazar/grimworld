import { createFundingChain } from "./chain.ts";
import { ConfigError, ENV, readConfig } from "./config.ts";
import { createFunderServer, createLogger } from "./http.ts";
import { fileLedger, memoryLedger } from "./ledger.ts";
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
const service = createFundingService({
  chain: createFundingChain(config),
  ledger: config.stateFile ? fileLedger(config.stateFile) : memoryLedger(),
  limits: {
    dailyBudget: config.dailyBudget,
    clientRate: config.clientRate,
    windowMs: HOUR_MS,
    settleMs: 60_000,
    pollMs: 500,
    holdMs: 5 * 60_000,
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
    process.exit(0);
  });
}
