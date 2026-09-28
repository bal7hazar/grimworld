# Changelog

What changed in the repository, newest first, one entry per merged task. Game results are
API (OPERATIONS §7): any change to the outcome of an action is announced here.

## 2026-09-28

- **FND-01 repository scaffold** ([#18](https://github.com/bal7hazar/grimworld/pull/18)): `contracts/` (Dojo package `grimworld`, namespaces `grimworld` and `grimworld_instance`, layering of CONTEXT §4) and the pnpm workspace `client/` (`@grimworld/sim` without rendering or chain dependency, `@grimworld/app` with PixiJS on demand). `origami_hexmap` 1.8.0 does not build on Cairo 2.13 (N-9). Report: [docs/reports/FND-01-scaffold.md](docs/reports/FND-01-scaffold.md).
- **SPK-5 toolchain pins** ([#14](https://github.com/bal7hazar/grimworld/pull/14)): the game is on **Cairo 2.13** (Scarb 2.13.1, snforge 0.51.2), Dojo 1.8 (sozo 1.8.7, Katana 1.7.1, Torii 1.8.16, `dojo` 1.8.0), Node 24.21.0, pnpm 12.5.1, dojo.js 2.0.0; `scripts/setup-toolchain.sh`, `scripts/with-katana.sh`; Torii self-hosted (Slot retired). Report: [docs/reports/SPK-5-toolchain.md](docs/reports/SPK-5-toolchain.md).
- **Launcher thresholds** ([#11](https://github.com/bal7hazar/grimworld/pull/11)): no agent starts or resumes above a 5-minute load of 12 or under 8 GB available (`scripts/agent.sh thresholds`); codex started through the system `node`; the `implement` profile denies direct agent-launch commands. Audit: [docs/reports/PR-11-launcher-thresholds-audit-gpt-6-sol.md](docs/reports/PR-11-launcher-thresholds-audit-gpt-6-sol.md).
- **FND-03 agent tooling** ([#8](https://github.com/bal7hazar/grimworld/pull/8)):
  `scripts/agent.sh` launcher, permission profiles `research` / `audit` / `implement`,
  build lock `scripts/lock.sh`, `docs/briefs/COMMON.md`, CI `tooling`. Report:
  [docs/reports/FND-03-agent-tooling.md](docs/reports/FND-03-agent-tooling.md).
