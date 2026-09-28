# [Opus 5.5] Incident — asdf `node` and `pnpm` shims break Node on the whole machine

Written by the game orchestrator, 2026-09-28 15:12 UTC. **Closed 2026-09-28**: remedy applied
by the project manager on the owner's explicit order (see *Outcome*).

## What happened

At 15:05 UTC, the Grim World agent `[Sonnet 5] SPK-5` (toolchain pins, brief
[docs/briefs/SPK-5-toolchain.md](../briefs/SPK-5-toolchain.md)) added the asdf plugins
`nodejs` and `pnpm` and installed `nodejs 24.21.0` and `pnpm 12.5.1`, as its brief asked
("install through asdf"). It did not touch the global `~/.tool-versions`, as the brief forbade.

Installing an asdf plugin also creates **shims** in `~/.asdf/shims/`: `node`, `npm`, `npx`,
`corepack`, `pnpm`, `pnpx`. On this machine `~/.asdf/shims` comes before `/usr/bin` on the
PATH of the user sessions and of the agents. In any directory without a `.tool-versions`
naming `nodejs` and `pnpm`, the shims now answer `No version is set for command node` instead
of falling through to `/usr/bin/node` (24.21) and `/usr/bin/pnpm` (12.5.1).

## Impact

| What | Effect, verified 15:10–15:12 UTC |
|---|---|
| `node`, `pnpm`, `npm` outside a pinned directory | Fail (`cd /tmp && node --version`) |
| `codex` (`/usr/bin/codex`, a Node script) | Fails: the game's audit `AUD-11` exited 126 at start |
| The owner's other programmes | **Likely affected** wherever they run Node, pnpm or codex from a directory without such a `.tool-versions` (for example a client build, or a codex audit). Not verified in their repositories |
| Grim World agents | ART-00 could not run `pnpm` (its AC-4 is pending); SPK-5 itself works in its worktree, which pins both |

Cause on our side: the SPK-5 brief did not foresee that adding an asdf plugin changes the
machine's PATH resolution for everyone. The orchestrator wrote that brief.

## Fix proposed (not applied)

Add two lines to the global `~/.tool-versions`:

```
nodejs system
pnpm system
```

With them, asdf falls through to the system binaries wherever no local version is set,
which is exactly the behaviour before 15:05; directories that pin a version (the Grim World
worktrees after SPK-5) keep their pin. Backup first (`cp ~/.tool-versions
~/.tool-versions.bak`); undo by removing the two lines.

The orchestrator tried to apply it and the session's permission classifier refused it as a
change to a shared resource. That refusal stands: it is the owner's or the project manager's
act. Alternatives: remove the six shims (`asdf` recreates them on the next `asdf install` or
`asdf reshim`), or uninstall the two plugins (breaks SPK-5's pins).

## Mitigation within the game's scope

- The game's launcher starts codex with `/usr/bin` ahead of the asdf shims, so that game
  audits work whatever the global setting ([PR](https://github.com/bal7hazar/grimworld/pulls)
  following this note).
- Future briefs that install a tool through asdf say that it creates machine-wide shims, and
  require `<tool> system` to work before the task ends, escalating otherwise.

## Outcome (closed 2026-09-28)

| | |
|---|---|
| Applied | `nodejs system` and `pnpm system` appended to the global `~/.tool-versions` by the project manager, on the owner's explicit order; backup in `~/.tool-versions.bak` |
| Verified by the project manager | From `/tmp`: `node` v24.21.0, `pnpm` 12.5.1, `codex-cli` 0.155.1, all exit 0; the SPK-5 worktree still resolves its pinned versions |
| Verified by the game orchestrator, 16:08 UTC | Same from `/tmp`; `npm` 11.19.0 works |
| Residual | `npm`, `npx` and `corepack` work but print one asdf line on stderr, `No version is set for nodejs; please run asdf set …`: **not a failure**, and no agent must treat it as one (docs/briefs/COMMON.md §3) |
| Kept as defence | The launcher starts codex through `/usr/bin/node` (PR #11) |
| Prevention | `scripts/setup-toolchain.sh` (SPK-5) no longer adds the `nodejs` or `pnpm` plugin when the system versions match the pins, and refuses to add one without a working system fallback. Every brief that installs a tool through asdf says that a plugin creates machine-wide shims (docs/briefs/COMMON.md §3) |
