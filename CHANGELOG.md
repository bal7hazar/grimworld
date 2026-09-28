# Changelog

What changed in the repository, newest first, one entry per merged task. Game results are
API (OPERATIONS §7): any change to the outcome of an action is announced here.

## 2026-09-28

- **Launcher thresholds** ([#11](https://github.com/bal7hazar/grimworld/pull/11)): no agent starts or resumes above a 5-minute load of 12 or under 8 GB available (`scripts/agent.sh thresholds`); codex started through the system `node`; the `implement` profile denies direct agent-launch commands. Audit: [docs/reports/PR-11-launcher-thresholds-audit-gpt-6-sol.md](docs/reports/PR-11-launcher-thresholds-audit-gpt-6-sol.md).
- **FND-03 agent tooling** ([#8](https://github.com/bal7hazar/grimworld/pull/8)):
  `scripts/agent.sh` launcher, permission profiles `research` / `audit` / `implement`,
  build lock `scripts/lock.sh`, `docs/briefs/COMMON.md`, CI `tooling`. Report:
  [docs/reports/FND-03-agent-tooling.md](docs/reports/FND-03-agent-tooling.md).
