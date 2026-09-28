# client

A pnpm workspace (root `package.json` and `pnpm-workspace.yaml`; Node and pnpm are pinned in
`.tool-versions`, run `scripts/setup-toolchain.sh` if one is missing). Two packages
([ADR-0003](../docs/architecture/ADR-0003-client.md)):

| Package                         | Role                                                                                          | May depend on                                                    |
| ------------------------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `@grimworld/sim` (`client/sim`) | Simulation core: pure TypeScript, deterministic                                               | nothing but itself: **no** PixiJS, React, dojo.js or starknet.js |
| `@grimworld/app` (`client/app`) | Vite, React, PixiJS 8 rendered **on demand** (no render loop), dojo.js 2.0.0 for chain access | `@grimworld/sim`                                                 |

Versions are exact and `pnpm-lock.yaml` is committed. Test runner: Vitest. Lint: ESLint with
`typescript-eslint` (`client/eslint.config.js`). Format: Prettier (`client/.prettierrc.json`).

## Build and test

From the repository root, through the build lock:

```
scripts/lock.sh pnpm install --frozen-lockfile
scripts/lock.sh pnpm test
scripts/lock.sh pnpm lint
scripts/lock.sh pnpm typecheck
scripts/lock.sh pnpm build
```

The root scripts run `pnpm -r …`; one package: `pnpm --filter @grimworld/sim test`. Format with
`pnpm format`. The dev server is `pnpm --filter @grimworld/app dev`.
