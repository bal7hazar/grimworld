# tools/site — the client of `main`, served for the owner's reviews

`grimworld.bal7hazar.com` serves the client of `origin/main`, rebuilt when main moves.

## What `deploy-site.sh` does

Run every 5 minutes by `grimworld-site.timer` (it can also be run by hand):

1. Works in its **own clone**, `~/site/grimworld-src` (never the shared checkout the threads use), and
   `git fetch origin main` there. Git only: no GitHub API call. Nothing to do when the commit and the art
   flag are those already deployed.
2. Builds the client only (`pnpm --filter @grimworld/app... install --frozen-lockfile`, then the app's
   `build`: `tsc --noEmit && vite build`) under `nice`. No Cairo, so no build lock.
3. Copies `client/app/dist` to `~/site/grimworld/releases/<sha>/` and switches `~/site/grimworld/current`
   to it atomically (`ln -sfn` to a temp name, then `mv -T`). The last 3 releases are kept; older ones it
   made are deleted. A failed build leaves `current` untouched; the failed sha is retried after 30 min.
4. Logs one line per run (sha, art flag, result, duration) to `~/site/grimworld/deploy.log`; the journal
   (`journalctl --user -u grimworld-site`) has the time of each step.

**Art (D-73).** Off by default: the client draws shapes. With `GRIMWORLD_SITE_ART=1` (a line in the
service, commented out) the script builds the atlas from `~/projects/assets` with `tools/art/build.py`
and copies it to `<release>/art/`, where the client loads it. Leave it unset until the owner decides
whether the art may be served (behind basic auth or publicly). Nothing of the art is in the repository.

The client has no chain endpoint configured: it talks to no network from the site.

## Owner's install steps

The timer is not installed by CI or by the agents. As `claude` (lingering is already on):

    mkdir -p ~/site/grimworld && chmod o+x ~/site ~/site/grimworld
    git clone git@github.com:bal7hazar/grimworld.git ~/site/grimworld-src   # skip if it exists
    mkdir -p ~/.config/systemd/user
    cp tools/site/grimworld-site.service tools/site/grimworld-site.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now grimworld-site.timer

As root, so that Caddy (user `caddy`) can read the site: `/home/claude` is `drwxr-x---` claude:claude, so

    sudo setfacl -m u:caddy:x /home/claude

(execute permission on that one directory for `caddy` only; `~/site` and `~/site/grimworld` need `o+x`,
done above, and the script makes each release `a+rX`).

Then the Caddy block, `Caddyfile.grimworld`, as root:

    caddy hash-password          # asks for the password, prints a bcrypt hash: paste it in the block
    sudo cp tools/site/Caddyfile.grimworld /etc/caddy/conf.d/grimworld.caddy   # or append to /etc/caddy/Caddyfile
    sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy

The `basic_auth` block is there so that the site is private; remove it to make the site public (the
owner's decision). No password or hash is committed.
