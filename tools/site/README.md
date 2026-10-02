# tools/site — the client of `main`, served for the owner's reviews

`grimworld.bal7hazar.com` serves the client of `origin/main`, rebuilt when main moves.

## What `deploy-site.sh` does

Run every 5 minutes by `grimworld-site.timer` (it can also be run by hand):

1. Works in its **own clone**, `~/site/grimworld-src` (never the shared checkout the threads use), and
   `git fetch origin main` there. Git only: no GitHub API call. Nothing to do when the commit and the art
   flag are those already deployed.
2. Builds the client only (`pnpm --filter @grimworld/app... install --frozen-lockfile`, then the app's
   `build`: `tsc --noEmit && vite build`) under `nice`. No Cairo, so no build lock.
3. Copies `client/app/dist` to `~/site/grimworld/releases/<sha>-<UTC time>/` and switches `~/site/grimworld/current`
   to it atomically (`ln -sfn` to a temp name, then `mv -T`). The last 3 releases are kept; older ones it
   made are deleted. A failed build leaves `current` untouched; the failed sha is retried after 30 min.
4. Logs one line per run (sha, art flag, result, duration) to `~/site/grimworld/deploy.log`; the journal
   (`journalctl --user -u grimworld-site`) has the time of each step.

**Art (D-73).** Off by default: the client draws shapes. With `GRIMWORLD_SITE_ART=1` (a line in the
service, commented out) the script builds the atlas from `~/projects/assets` with `tools/art/build.py`
and copies `sprites.json` and the pages it lists (not `report.json` or `preview.html`) to `<release>/art/`, where the client loads it. Leave it unset until the owner decides
whether the art may be served (behind basic auth or publicly). Nothing of the art is in the repository.

The client has no chain endpoint configured: it talks to no network from the site.

## Owner's install steps

The timer is not installed by CI or by the agents. As `claude` (lingering is already on):

    mkdir -p ~/site/grimworld && chmod o+x ~/site ~/site/grimworld
    git clone https://github.com/bal7hazar/grimworld.git ~/site/grimworld-src   # skip if it exists
    mkdir -p ~/.config/systemd/user
    cp tools/site/grimworld-site.service tools/site/grimworld-site.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now grimworld-site.timer

As root, so that Caddy (user `caddy`) can read the site: `/home/claude` is `drwxr-x---` claude:claude, so

    sudo setfacl -m u:caddy:x /home/claude

(execute permission on that one directory for `caddy` only; `~/site` and `~/site/grimworld` need `o+x`,
done above, and the script makes each release `a+rX`).

Then the Caddy block, `Caddyfile.grimworld`. The commands run from `~/site/grimworld-src`
(`cd ~/site/grimworld-src`; before the PR is merged, from the worktree that has the file). Get the hash
first (`caddy hash-password` asks for the password and prints a bcrypt hash) and paste it in place of the
placeholder in your copy of the block. Then, on a stock Caddyfile, append the block:

    sudo sh -c 'cat tools/site/Caddyfile.grimworld >> /etc/caddy/Caddyfile'
    sudo caddy validate --config /etc/caddy/Caddyfile
    sudo systemctl reload caddy

(or add the line `import /etc/caddy/conf.d/*.caddy` to `/etc/caddy/Caddyfile` first and copy the block to
`/etc/caddy/conf.d/grimworld.caddy`).

The `basic_auth` block is there so that the site is private; remove it to make the site public (the
owner's decision). No password or hash is committed.

## Runtime notes

- The service runs `/usr/bin/node` 24.21.0 and `/usr/bin/pnpm` 12.5.1 (the versions of `.tool-versions`),
  from an explicit `Environment=PATH=/usr/local/bin:/usr/bin:/bin`.
- The clone uses HTTPS (the repository is public): a unit has no `SSH_AUTH_SOCK`, so an SSH remote would
  need a passphrase-less key or a deploy key. The script sets the clone's `origin` to that URL on each run
  (`GRIMWORLD_SITE_REPO` overrides it).
- `deploy.log` has a line per deploy or failed build only. If the service fails before the script starts
  (the `git fetch` or `checkout` of `ExecStartPre`), nothing is logged there: look at
  `journalctl --user -u grimworld-site`.
- Each release is `releases/<sha>-<UTC time>`: a redeploy of the same commit (for instance after
  `rm ~/site/grimworld/deployed`) creates a new directory, switches `current`, then prunes to the last 3
  and removes leftover `*.tmp` directories.
