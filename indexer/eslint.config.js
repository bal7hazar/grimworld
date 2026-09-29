// The client's rules (client/eslint.config.js), for the indexer's sources and tests.
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["**/dist/", "**/node_modules/", "emitter/", ".scratch/"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
);
