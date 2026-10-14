import { AccountError, type AccountProvider, type Call, type ExecutionStatus } from "../account";
import type { Reader } from "../preview";
import type { Credit } from "./credit";

/**
 * The burner's own player (CLI-11 §3.1, §3.4): an account of the Hub, an adventurer, and that
 * adventurer inside an instance. The burner never plays the deployment's adventurer (account 0
 * controls it). At every session, and again after an instance closes, `restore` reads the views and
 * sends only what is missing, each step its own execution, so a step that fails leaves what was done
 * in place and the next pass resumes from the views. Nothing is kept beside the key.
 *
 * With the deployment's build (CLI-11d3, SEED-02's four skills and belt), the first entry follows
 * track game's `devnet_deploy.py --credit-only` order: the adventurer enters built empty, the
 * development server credits it (`Credit`, account 0's calls node-side), and it leaves by gate 2,
 * buys the bar's skills and sets the build, in one execution, before it enters again built. Whether
 * it was built is read from the Hub's view of the adventurer, its stored `Build` word (`builtWith`).
 */

/** The node's pre-funded account that funds burners (0 is the deployment's; §3.1). */
export const FUNDER_INDEX = 1;
/** STRK given to each new burner: 100 STRK, in fri. */
export const BURNER_FUNDS = 10n ** 20n;
/** An empty bar (elite slot 255 at bit 168), as `scripts/devnet_deploy.py` sets it. */
export const EMPTY_BUILD = 255n << 168n;
/** The gate entered: gate 1, the start hub's gate into the test zone (`devnet_deploy.py`). */
export const START_GATE = 1;
/** The gate left by after the credit: gate 2, from the zone back to the start hub. */
export const BACK_GATE = 2;
/** `LIVE`, bit 250, which the Hub adds to every word `set_build` stores. */
export const LIVE = 1n << 250n;
/** The burner's adventurer: `'Burner'`, a short string, of profession 1. */
export const BURNER_NAME = 0x4275726e6572n;
export const PROFESSION = 1;

/** Selectors of the Hub's views read here (`sn_keccak` of the names), held by `setup.test.ts`. */
export const hubSelector = {
  account_of: 0x3a8811430aebb75d552578aa4b5de4d0be0630bc4d3f4d82ea3fd41242de6f9n,
  account: 0x44bb55167ab332117049e2ccd3d8863d241bcc80f46302310a6d942a90e851n,
  adventurer: 0x1a82266d2da31bf0340cc21e4ed21b2b94e4e461e52519e39146953d9d63ca0n,
} as const;

/** `content::GATE`, the Registry's kind of a gate record. */
const GATE = 4;
/** `Adventurer`'s place word (`IHubViews::adventurer`, word 1): bits 64-79 hold its hub. */
const PLACE = 1;
/** `Adventurer`'s stored `Build` word (word 2): what the last `set_build` sent, plus `LIVE`. */
const BUILD = 2;

/** The deployment's build (its JSON's `build` key, mode `full`): the bar's eight skills, the belt. */
export interface Build {
  readonly bar: readonly number[];
  readonly belt: readonly { readonly item: number; readonly count: number }[];
}

/** `set_build`'s `Build` word, as `devnet_deploy.py`'s `build_word`: 16 bits a slot, no elite. */
export function buildWord(bar: readonly number[]): bigint {
  return bar.reduce(
    (word, skill, slot) => word + (BigInt(skill) << BigInt(16 * slot)),
    EMPTY_BUILD,
  );
}

/** `set_build`'s belt word, as `belt_word`: the items in lanes 0-3, their counts in lane 4. */
export function beltWord(belt: Build["belt"]): bigint {
  const items = belt.reduce(
    (word, { item }, lane) => word + (BigInt(item) << BigInt(32 * lane)),
    0n,
  );
  const counts = belt.reduce(
    (word, { count }, lane) => word + (BigInt(count) << BigInt(8 * lane)),
    0n,
  );
  return items + (counts << 128n);
}

export interface SetupDeps {
  readonly provider: AccountProvider;
  readonly reader: Pick<Reader, "call" | "placement" | "record" | "instanceState">;
  readonly hub: string;
  readonly instances: string;
  readonly registry: string;
  /** The deployment's build (CLI-11d3); without it the adventurer enters built empty. */
  readonly build?: Build;
  /** The development server's credit, which the first entry with `build` needs. */
  readonly credit?: Credit;
  /** Between two asks of an execution's status, in ms. */
  readonly pollMs?: number;
}

/** Where the burner's player stands once restored: inside an instance. */
export interface Player {
  readonly address: string;
  readonly adventurerId: number;
  readonly instanceId: bigint;
  /** The member it controls (`placement.member`). */
  readonly member: number;
}

/** An execution of the setup did not succeed: its step, and the status it ended on. */
export class SetupFailed extends Error {
  constructor(
    readonly step: string,
    readonly status: ExecutionStatus,
  ) {
    super(`setup: ${step} ${status}`);
    this.name = "SetupFailed";
  }
}

const u32 = (felt: bigint | undefined, what: string): number => {
  if (felt === undefined || felt >= 1n << 32n) throw new RangeError(`${what}: not a u32`);
  return Number(felt);
};

/** Sends one execution and waits until it settles; anything but `succeeded` is `SetupFailed`. */
async function run(deps: SetupDeps, step: string, calls: Call[]): Promise<void> {
  const id = await deps.provider.execute(calls);
  const pollMs = deps.pollMs ?? 250;
  for (;;) {
    const status = await deps.provider.status(id);
    if (status === "succeeded") return;
    if (status !== "pending") throw new SetupFailed(step, status);
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
}

/** `Hub.account_of(address)`: 0 when the address has no account. */
async function accountOf(deps: SetupDeps, address: string): Promise<number> {
  const [id] = await deps.reader.call(deps.hub, hubSelector.account_of, [BigInt(address)]);
  return u32(id, "account_of");
}

/** `Hub.account(id)`'s adventurers: `(owner, record, Span<u32>)`, the span's ids. */
async function adventurersOf(deps: SetupDeps, accountId: number): Promise<number[]> {
  const felts = await deps.reader.call(deps.hub, hubSelector.account, [BigInt(accountId)]);
  const [, , length, ...ids] = felts;
  if (length === undefined || Number(length) !== ids.length) {
    throw new RangeError("account: not a span");
  }
  return ids.map((id) => u32(id, "account"));
}

/** `Hub.adventurer(id)`: its six words. */
async function wordsOf(deps: SetupDeps, adventurerId: number): Promise<bigint[]> {
  // A `Span<felt252>`: its length, then the six words
  const [length, ...words] = await deps.reader.call(deps.hub, hubSelector.adventurer, [
    BigInt(adventurerId),
  ]);
  if (length !== 6n || words.length !== 6) throw new RangeError("adventurer: not six words");
  return words;
}

/** The hub the adventurer stands in (`Hub.adventurer(id)`, its place word): 0 inside an instance. */
export async function hubOf(deps: SetupDeps, adventurerId: number): Promise<number> {
  const place = (await wordsOf(deps, adventurerId))[PLACE]!;
  return Number((place >> 64n) & 0xffffn);
}

/**
 * Whether the adventurer was built with `build`'s bar: its stored `Build` word, `LIVE` aside, is
 * the bar's word. `set_build` refuses a bar of skills the adventurer does not know, so this also
 * says that it knows them. The views of known skills and of the pack panic NOT_IMPLEMENTED, and a
 * flag kept beside the key would outlive the node it was true on (a restarted node keeps the
 * burner's key, not its adventurer): the stored word is the chain's own answer, and a reload or a
 * second provider reads the same.
 */
export async function builtWith(deps: SetupDeps, adventurerId: number, build: Build) {
  const stored = (await wordsOf(deps, adventurerId))[BUILD]!;
  return (stored & ~LIVE) === buildWord(build.bar);
}

/** Gate `gate`'s source location (its Registry record, bits 0-15 of its first part). */
export async function gateSource(deps: SetupDeps, gate: number): Promise<number> {
  const [first] = await deps.reader.record(deps.registry, GATE, gate);
  if (first === undefined || first === 0n) throw new RangeError(`gate ${gate}: no record`);
  return Number(first & 0xffffn);
}

const call = (to: string, entrypoint: string, ...calldata: bigint[]): Call => ({
  to,
  entrypoint,
  calldata,
});

/** An error worth one more try once a credit ran: a failed or refused execution of the burner. */
const refusedSend = (error: unknown): boolean =>
  error instanceof SetupFailed ||
  (error instanceof AccountError &&
    error.code === "refused" &&
    !(error.cause instanceof Error && error.cause.name === "ChainRefused"));

/**
 * The chain refused the full build: the fee estimate was refused, or the execution ran and
 * failed. Any other `SetupFailed` (a status that stayed `unknown`) is not a refusal of the build.
 */
const refusedBuild = (error: unknown): boolean =>
  (error instanceof SetupFailed && error.status === "failed") ||
  (error instanceof AccountError &&
    error.code === "refused" &&
    !(error.cause instanceof Error && error.cause.name === "ChainRefused"));

/** Until no credit runs: polled at the execution's pace. */
async function idle(deps: SetupDeps, credit: Credit): Promise<void> {
  for (;;) {
    const { state } = await credit.status();
    if (state === "unusable") await credit.assertUsable();
    if (state !== "running") return;
    await new Promise((resolve) => setTimeout(resolve, deps.pollMs ?? 250));
  }
}

/**
 * `run` for an `enter` or a `leave` (caveat a of `--credit-only`): while a credit runs, the Hub's
 * `instances` is account 0 for a few transactions and they revert. So it waits while one runs, and
 * an execution that failed while one ran (the count of credits moved, or one is running) is sent
 * again after it, at most twice, never shown as a failure. Without a credit, `run`.
 */
async function runAround(deps: SetupDeps, step: string, calls: Call[]): Promise<void> {
  const { credit } = deps;
  if (credit === undefined) return run(deps, step, calls);
  for (let attempt = 0; ; attempt++) {
    await idle(deps, credit);
    const before = await credit.status();
    try {
      return await run(deps, step, calls);
    } catch (error) {
      if (attempt >= 2 || !refusedSend(error)) throw error;
      const after = await credit.status();
      if (after.state === "unusable") await credit.assertUsable();
      if (after.state !== "running" && after.credits === before.credits) throw error;
    }
  }
}

/** `Hub.travel` to gate 1's source first, only when the adventurer stands in another hub. */
async function toStartHub(deps: SetupDeps, adventurerId: number): Promise<void> {
  const [here, source] = await Promise.all([
    hubOf(deps, adventurerId),
    gateSource(deps, START_GATE),
  ]);
  if (here !== source) {
    await run(deps, "travel", [call(deps.hub, "travel", BigInt(adventurerId), BigInt(source))]);
  }
}

/**
 * Steps 2 and 3 of `--credit-only` for an adventurer inside `instanceId`: the development server's
 * credit (260 gold, the pack of twice the belt), then one execution that leaves by gate 2 at the
 * instance's sequence, buys the bar's skills and sets the build. One execution, so the skills are
 * known exactly when the build is stored: a half-bought bar, which `buy_skill` would refuse to
 * buy again, cannot happen. A leave the chain refuses (the member off the gate's anchor) returns
 * without a revert, and the `buy_skill` after it reverts the whole execution (`NOT_IN_HUB`).
 */
async function creditAndBuild(
  deps: SetupDeps,
  adventurerId: number,
  instanceId: bigint,
  build: Build,
): Promise<void> {
  if (deps.credit === undefined) throw new SetupFailed("credit", "unknown");
  const id = BigInt(adventurerId);
  await deps.credit.credit(adventurerId);
  const { sequence } = (await deps.reader.instanceState(deps.instances, instanceId)).header;
  const leave = call(deps.instances, "leave", instanceId, id, BigInt(sequence), BigInt(BACK_GATE));
  const buy = build.bar
    .filter((skill) => skill !== 0)
    .map((skill) => call(deps.hub, "buy_skill", id, BigInt(skill)));
  const set = call(deps.hub, "set_build", id, buildWord(build.bar), beltWord(build.belt), 0n);
  await runAround(deps, "build", [leave, ...buy, set]);
}

/**
 * Step 4 of §3.4: the adventurer, in a hub, enters gate `START_GATE`. `Hub.travel` first only when
 * its hub is not the gate's source; `Hub.set_build` before every `enter` (the views cannot show
 * whether an earlier one ran, and it overwrites); `Hub.enter` alone, because the entry draws Fate.
 * This is also what `N` runs after an instance closes.
 *
 * With `deps.build` (CLI-11d3): an adventurer already built with it (`builtWith`) sends the build,
 * bar and belt; when the chain refuses that (its fee estimate refused, or the execution failed: the
 * pack no longer covers the belt, the potions spent), the bar alone with an empty belt, which needs
 * no pack. One not built yet enters built empty, is credited and built inside (`creditAndBuild`),
 * and enters again from the start hub.
 */
export async function enter(deps: SetupDeps, adventurerId: number): Promise<void> {
  const id = BigInt(adventurerId);
  const { build } = deps;
  await toStartHub(deps, adventurerId);
  if (build !== undefined && (await builtWith(deps, adventurerId, build))) {
    const bar = buildWord(build.bar);
    try {
      await run(deps, "set_build", [
        call(deps.hub, "set_build", id, bar, beltWord(build.belt), 0n),
      ]);
    } catch (error) {
      if (!refusedBuild(error)) throw error;
      await run(deps, "set_build", [call(deps.hub, "set_build", id, bar, 0n, 0n)]);
    }
    await runAround(deps, "enter", [call(deps.hub, "enter", id, BigInt(START_GATE))]);
    return;
  }
  await run(deps, "set_build", [call(deps.hub, "set_build", id, EMPTY_BUILD, 0n, 0n)]);
  await runAround(deps, "enter", [call(deps.hub, "enter", id, BigInt(START_GATE))]);
  if (build === undefined) return;
  const placement = await deps.reader.placement(deps.instances, adventurerId);
  if (!placement.inside) throw new SetupFailed("enter", "unknown");
  await creditAndBuild(deps, adventurerId, placement.instanceId, build);
  await toStartHub(deps, adventurerId);
  await runAround(deps, "enter", [call(deps.hub, "enter", id, BigInt(START_GATE))]);
}

/**
 * The burner's player, restored from the views or made: (1) no account, `register` and
 * `create_adventurer` in one execution; (2) an account with no adventurer, `create_adventurer`
 * alone; (3) an adventurer inside an instance is played, nothing sent, unless the deployment has a
 * build it was not given yet (a setup stopped between its empty entry and its build): it is then
 * credited, built and entered again; (4) otherwise it enters.
 */
export async function restore(deps: SetupDeps): Promise<Player> {
  const { address } = await deps.provider.createOrRestore();
  const create = call(deps.hub, "create_adventurer", BURNER_NAME, BigInt(PROFESSION));
  let accountId = await accountOf(deps, address);
  if (accountId === 0) {
    await run(deps, "register", [call(deps.hub, "register"), create]);
    accountId = await accountOf(deps, address);
    if (accountId === 0) throw new SetupFailed("register", "unknown");
  }
  let adventurers = await adventurersOf(deps, accountId);
  if (adventurers.length === 0) {
    await run(deps, "create_adventurer", [create]);
    adventurers = await adventurersOf(deps, accountId);
  }
  const adventurerId = adventurers[0];
  if (adventurerId === undefined) throw new SetupFailed("create_adventurer", "unknown");
  let placement = await deps.reader.placement(deps.instances, adventurerId);
  const { build } = deps;
  if (placement.inside && build !== undefined && !(await builtWith(deps, adventurerId, build))) {
    await creditAndBuild(deps, adventurerId, placement.instanceId, build);
    await toStartHub(deps, adventurerId);
    await runAround(deps, "enter", [
      call(deps.hub, "enter", BigInt(adventurerId), BigInt(START_GATE)),
    ]);
    placement = await deps.reader.placement(deps.instances, adventurerId);
    if (!placement.inside) throw new SetupFailed("enter", "unknown");
  } else if (!placement.inside) {
    await enter(deps, adventurerId);
    placement = await deps.reader.placement(deps.instances, adventurerId);
    if (!placement.inside) throw new SetupFailed("enter", "unknown");
  }
  return { address, adventurerId, instanceId: placement.instanceId, member: placement.member };
}
