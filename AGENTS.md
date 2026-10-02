# Agents' notes

- Once per clone, enable the repository's hooks: `git config core.hooksPath .githooks`.
- Before every push, run `scripts/prepush.sh`. It decides from your diff which of CI's checks to run (format,
  script self-tests, the build of the Cairo packages you touched, the generated artefacts, the client) and prints
  each step's time. The pre-push hook runs it for you once the hooks are enabled.
- Never push red: fix what it reports first. CI stays the gate; this is the same checks, earlier.
- `scripts/prepush.sh --all` runs every check whatever the diff: use it when you change the toolchain pins, a
  workflow or a script that the checks share.
- Heavy builds and tests go through `scripts/lock.sh`; the rules of the repository are in `docs/briefs/COMMON.md`
  and `OPERATIONS.md`.
