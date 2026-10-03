# tools/site — the client of `main`, served publicly for the owner's reviews

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

**Art (D-73).** On, by the owner's decision of 2026-10-02 that the pack's illustrations are served on the
public site: the service sets `GRIMWORLD_SITE_ART=1`. The script builds the atlas from `~/projects/assets`
with `tools/art/build.py` and copies **only the built atlas** to `<release>/art/`: `sprites.json`, the pages
it lists and their images. Never `report.json`, `preview.html` or a raw file of the pack, and nothing of
the pack is committed (the repository holds none). Without the variable the client draws shapes.

The client has no chain endpoint configured: it talks to no network from the site.

## Owner's install steps

The timer is not installed by CI or by the agents. As `claude` (lingering is already on), from
`~/site/grimworld-src` (the `cp` below is relative to it):

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

The Caddy block, `Caddyfile.grimworld`, serves the site **publicly**: the owner decided so on 2026-10-02.
It is already appended to the end of `/etc/caddy/Caddyfile` on this VPS (there is no conf.d); to change
it, edit that file as root, then `sudo caddy validate --config /etc/caddy/Caddyfile` and
`sudo systemctl reload caddy`. `basic_auth` is an option, not the default: a commented example is in the
block (hash from `caddy hash-password`; never commit a real one).

## Runtime notes

- The service runs `/usr/bin/node` 24.21.0 and `/usr/bin/pnpm` 12.5.1 (the versions of `.tool-versions`),
  from an explicit `Environment=PATH=/usr/local/bin:/usr/bin:/bin`.
- The clone uses HTTPS (the repository is public): a unit has no `SSH_AUTH_SOCK`, so an SSH remote would
  need a passphrase-less key or a deploy key. The unit sets the clone's `origin` to that URL in an `ExecStartPre` before its
  `git fetch`, and the script does the same on each run (`GRIMWORLD_SITE_REPO` overrides it for the
  script only).
- `deploy.log` has a line per deploy or failed build only. If the service fails before the script starts
  (the `git fetch` or `checkout` of `ExecStartPre`), nothing is logged there: look at
  `journalctl --user -u grimworld-site`.
- Each release is `releases/<sha>-<UTC time>`: a redeploy of the same commit (for instance after
  `rm ~/site/grimworld/deployed`) creates a new directory, switches `current`, then prunes to the last 3
  and removes leftover `*.tmp` directories.
