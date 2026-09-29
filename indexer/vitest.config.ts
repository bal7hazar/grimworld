import { defineConfig } from "vitest/config";

// Unit tests: no network, no node (a fake JSON-RPC, src/testing/). The local-node scenario has its
// own configuration (vitest.node.config.ts, `pnpm test:node`).
export default defineConfig({
  test: { include: ["src/**/*.test.ts"] },
});
