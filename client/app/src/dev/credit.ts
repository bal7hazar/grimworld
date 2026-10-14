import { spawn as spawnProcess } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * The development server's `/devnet/credit` (CLI-11d3; used by `vite.config.ts` and the chain's node
 * test, never by the app): it runs track game's `scripts/devnet_deploy.py --credit-only` for one
 * adventurer, node-side, and answers its JSON. The browser gives the adventurer's id and nothing
 * else: no key, no address of account 0, no path. Account 0's calls (`set_contracts`, the forged
 * `report`) stay in game's script; nothing here or in the app sends them (D-273, CLI-11 §3.4).
 *
 * - `POST` with `{"adventurer": <id>}` (`application/json`): one credit, after any credit already
 *   queued (the script also takes a lock file in `$WITH_NODE_LOG_DIR`, caveat b). 200 with
 *   `{adventurer_id, instance_id, gold, pack}`; 400 for any other body; 404 without a deployment;
 *   403 when the deployment has no full `build` key or its node is not local; 502 when the script
 *   failed (its last `devnet_deploy:` line); 409 once the devnet is unusable.
 * - `GET`: `{state, credits}`, `state` one of `idle`, `running` or `unusable`, `credits` the number
 *   of credits started. The burner reads it around its own `enter` and `leave` (caveat a: while a
 *   credit runs, `Hub.instances` is account 0 and they revert), and before every send (caveat c).
 *
 * Loopback only: a request whose remote address is not `127.0.0.1` or `::1` (or `::ffff:127.0.0.1`,
 * how a dual-stack socket reports the IPv4 loopback) is refused, 403, before its body is read
 * (`--host 0.0.0.0` would otherwise open it to the network). The endpoint lives in Vite's dev
 * middleware only (`apply: "serve"`): `vite build` carries none of it.
 *
 * A run that outlives `timeoutMs` is killed, its own child process only, by its pid. A killed run
 * may leave `Hub.instances` pointing at account 0, and the next run does not repair it (game's
 * review), so from then on the devnet is unusable: every credit is refused, and the app refuses
 * every chain action with "devnet left mid-credit: redeploy". Nothing repairs it but a new
 * deployment.
 */

export type CreditState = "idle" | "running" | "unusable";

/** The remote addresses of this machine that may call the endpoint. */
const LOOPBACK: ReadonlySet<string> = new Set(["127.0.0.1", "::1", "::ffff:127.0.0.1"]);

/** Whether a request's remote address is the machine's own. */
export const fromLoopback = (remote: string | undefined): boolean =>
  remote !== undefined && LOOPBACK.has(remote);

/** What the runner uses of the script's process (`ChildProcess`'s part, so tests fake it). */
export interface CreditChild {
  readonly stdout: { on(event: "data", listener: (chunk: unknown) => void): unknown } | null;
  readonly stderr: { on(event: "data", listener: (chunk: unknown) => void): unknown } | null;
  on(event: "error", listener: (error: unknown) => void): unknown;
  on(event: "close", listener: (code: number | null) => void): unknown;
  kill(signal: "SIGKILL"): boolean;
}

export interface CreditAnswer {
  readonly status: 200 | 400 | 403 | 404 | 405 | 409 | 502;
  readonly body: string;
}

export interface Credited {
  readonly adventurer_id: number;
  readonly instance_id: number;
  readonly gold: number;
  readonly pack: readonly { readonly item: number; readonly count: number }[];
}

export interface CreditOptions {
  /** `GRIMWORLD_DEPLOYMENT`'s value: the file `devnet_deploy.py --out` wrote. */
  readonly deploymentPath: string | undefined;
  /** The repository's root: the script's folder's parent, and its working directory. */
  readonly root: string;
  /** How long one run may take before it is killed, in ms (default 180 000). */
  readonly timeoutMs?: number;
  /** The environment the script runs in (`process.env` by default; `NODE_URL` is dropped). */
  readonly env?: Readonly<Record<string, string | undefined>>;
  /** Starts the script (tests fake it). */
  readonly spawn?: (command: string, args: readonly string[], cwd: string) => CreditChild;
}

/** The line the app shows once the devnet is unusable (caveat c). */
export const UNUSABLE = "devnet left mid-credit: redeploy";
const TIMEOUT_MS = 180_000;
/** The only node the credit runs against: the local one, as the script itself requires. */
const LOCAL = /^http:\/\/127\.0\.0\.1:[0-9]{1,5}$/;

const json = (status: CreditAnswer["status"], value: unknown): CreditAnswer => ({
  status,
  body: JSON.stringify(value),
});
const refusal = (status: CreditAnswer["status"], error: string) => json(status, { error });

/** An adventurer's id: a whole number from 1 to 2^32 - 1. */
const adventurerId = (value: unknown): value is number =>
  typeof value === "number" && Number.isInteger(value) && value >= 1 && value < 2 ** 32;

/** Why the deployment cannot be credited, or undefined when it can. */
function refused(path: string | undefined): { status: 403 | 404; error: string } | undefined {
  if (path === undefined || path === "") return { status: 404, error: "no deployment" };
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return { status: 404, error: "no deployment" };
  }
  if (typeof parsed !== "object" || parsed === null) return { status: 404, error: "no deployment" };
  const { node_url, build } = parsed as { node_url?: unknown; build?: unknown };
  if (typeof node_url !== "string" || !LOCAL.test(node_url)) {
    return { status: 403, error: "the deployment's node is not local" };
  }
  if (
    typeof build !== "object" ||
    build === null ||
    (build as { mode?: unknown }).mode !== "full"
  ) {
    return { status: 403, error: "the deployment has no build" };
  }
  return undefined;
}

/** The script's answer, its known fields only. */
function credited(stdout: string): Credited | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    return undefined;
  }
  if (typeof parsed !== "object" || parsed === null) return undefined;
  const { adventurer_id, instance_id, gold, pack } = parsed as Record<string, unknown>;
  const whole = (value: unknown): value is number =>
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
  if (!whole(adventurer_id) || !whole(instance_id) || !whole(gold) || !Array.isArray(pack)) {
    return undefined;
  }
  const lanes = pack.map((lane: unknown) => {
    const { item, count } = (lane ?? {}) as { item?: unknown; count?: unknown };
    return whole(item) && whole(count) ? { item, count } : undefined;
  });
  if (lanes.some((lane) => lane === undefined)) return undefined;
  return { adventurer_id, instance_id, gold, pack: lanes as Credited["pack"] };
}

/** The script's last `devnet_deploy:` line (it never prints a key), at most 200 characters. */
function lastLine(stderr: string): string {
  const lines = stderr.split("\n").filter((line) => line.startsWith("devnet_deploy:"));
  return (lines.at(-1) ?? "devnet_deploy: failed").slice(0, 200);
}

export interface CreditRunner {
  /** `GET`. */
  state(): { readonly state: CreditState; readonly credits: number };
  /** `POST` with the body's text. */
  credit(body: string): Promise<CreditAnswer>;
  /** The request as the server receives it: its remote address, method, content type and body. */
  request(
    remote: string | undefined,
    method: string,
    contentType: string | undefined,
    body: string,
  ): Promise<CreditAnswer>;
}

export function createCreditRunner(options: CreditOptions): CreditRunner {
  const timeoutMs = options.timeoutMs ?? TIMEOUT_MS;
  const start =
    options.spawn ??
    ((command: string, args: readonly string[], cwd: string) => {
      const env = { ...(options.env ?? process.env) };
      // The deployment's own node, which `refused` checked, not one the environment names
      delete env.NODE_URL;
      return spawnProcess(command, args, {
        cwd,
        env,
        stdio: ["ignore", "pipe", "pipe"],
      }) as unknown as CreditChild;
    });
  let unusable = false;
  let running = 0;
  let credits = 0;
  /** Credits run one at a time, in the order asked. */
  let queue: Promise<unknown> = Promise.resolve();

  function run(adventurer: number, path: string): Promise<CreditAnswer> {
    return new Promise((resolve) => {
      const child = start(
        "python3",
        [
          join(options.root, "scripts", "devnet_deploy.py"),
          "--credit-only",
          "--deployment",
          path,
          "--adventurer",
          String(adventurer),
        ],
        options.root,
      );
      let stdout = "";
      let stderr = "";
      let killed = false;
      child.stdout?.on("data", (chunk) => (stdout += String(chunk)));
      child.stderr?.on("data", (chunk) => (stderr += String(chunk)));
      const timer = setTimeout(() => {
        // Its own child only, by its pid; the devnet is unusable from now on (caveat c)
        killed = true;
        unusable = true;
        child.kill("SIGKILL");
      }, timeoutMs);
      const settle = (code: number | null) => {
        clearTimeout(timer);
        if (killed) {
          resolve(refusal(409, UNUSABLE));
          return;
        }
        const answer = code === 0 ? credited(stdout) : undefined;
        resolve(answer ? json(200, answer) : refusal(502, lastLine(stderr)));
      };
      child.on("error", () => settle(null));
      child.on("close", settle);
    });
  }

  async function credit(body: string): Promise<CreditAnswer> {
    let parsed: unknown;
    try {
      parsed = JSON.parse(body);
    } catch {
      return refusal(400, "the body is not JSON");
    }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return refusal(400, "the body is not an object");
    }
    const keys = Object.keys(parsed);
    const { adventurer } = parsed as { adventurer?: unknown };
    if (keys.length !== 1 || !adventurerId(adventurer)) {
      return refusal(400, 'the body is {"adventurer": <id>} and nothing else');
    }
    const path = options.deploymentPath;
    const why = refused(path);
    if (why) return refusal(why.status, why.error);
    const next = queue.then(async (): Promise<CreditAnswer> => {
      if (unusable) return refusal(409, UNUSABLE);
      running += 1;
      credits += 1;
      try {
        return await run(adventurer, path!);
      } finally {
        running -= 1;
      }
    });
    queue = next.catch(() => undefined);
    return next;
  }

  const state = () => ({
    state: (unusable ? "unusable" : running > 0 ? "running" : "idle") as CreditState,
    credits,
  });
  return {
    state,
    credit,
    async request(remote, method, contentType, body) {
      if (!fromLoopback(remote)) return refusal(403, "loopback only");
      if (method === "GET") return json(200, state());
      if (method !== "POST") return refusal(405, "GET or POST");
      // A JSON body: a page of another origin cannot send it without a preflight
      if (!contentType?.split(";")[0]?.trim().toLowerCase().startsWith("application/json")) {
        return refusal(400, "the body is application/json");
      }
      return credit(body);
    },
  };
}
