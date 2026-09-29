import { defineConfig } from "vitest/config";

// The local-node scenario (`pnpm test:node`, under scripts/with-node.sh): one file, in order, with
// the time a node needs.
export default defineConfig({
  test: {
    include: ["test-node/**/*.node.test.ts"],
    testTimeout: 600_000,
    hookTimeout: 120_000,
    fileParallelism: false,
  },
});
