// The client's rules (client/eslint.config.js), for the indexer's sources and tests.
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["**/dist/", "**/node_modules/", "emitter/", ".scratch/"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    // The client library runs in a browser (IDX-01b): no Node module, nothing outside its folder.
    files: ["src/client/**/*.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["node:*"],
              message: "the client library runs in a browser",
            },
            {
              group: ["../*"],
              message: "the client library imports only its own folder",
            },
          ],
        },
      ],
    },
  },
);
