import type { AccountProvider, Call, ExecutionStatus } from "../account";
import type { Reader } from "../preview";

/**
 * The burner's own player (CLI-11 §3.1, §3.4): an account of the Hub, an adventurer, and that
 * adventurer inside an instance. The burner never plays the deployment's adventurer (account 0
 * controls it). At every session, and again after an instance closes, `restore` reads the views and
 * sends only what is missing, each step its own execution, so a step that fails leaves what was done
 * in place and the next pass resumes from the views. Nothing is kept beside the key.
 */

/** The node's pre-funded account that funds burners (0 is the deployment's; §3.1). */
export const FUNDER_INDEX = 1;
/** STRK given to each new burner: 100 STRK, in fri. */
export const BURNER_FUNDS = 10n ** 20n;
/** An empty bar (elite slot 255 at bit 168), as `scripts/devnet_deploy.py` sets it. */
export const EMPTY_BUILD = 255n << 168n;
/** The gate entered: gate 1, the start hub's gate into the test zone (`devnet_deploy.py`). */
export const START_GATE = 1;
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

export interface SetupDeps {
  readonly provider: AccountProvider;
  readonly reader: Pick<Reader, "call" | "placement" | "record">;
  readonly hub: string;
  readonly instances: string;
  readonly registry: string;
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

/** The hub the adventurer stands in (`Hub.adventurer(id)`, its place word): 0 inside an instance. */
export async function hubOf(deps: SetupDeps, adventurerId: number): Promise<number> {
  // A `Span<felt252>`: its length, then the six words
  const [length, ...words] = await deps.reader.call(deps.hub, hubSelector.adventurer, [
    BigInt(adventurerId),
  ]);
  const place = words[PLACE];
  if (length !== 6n || words.length !== 6 || place === undefined) {
    throw new RangeError("adventurer: not six words");
  }
  return Number((place >> 64n) & 0xffffn);
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

/**
 * Step 4 of §3.4: the adventurer, in a hub, enters gate `START_GATE`. `Hub.travel` first only when
 * its hub is not the gate's source; `Hub.set_build` before every `enter` (the views cannot show
 * whether an earlier one ran, and it overwrites); `Hub.enter` alone, because the entry draws Fate.
 * This is also what `N` runs after an instance closes.
 */
export async function enter(deps: SetupDeps, adventurerId: number): Promise<void> {
  const id = BigInt(adventurerId);
  const [here, source] = await Promise.all([
    hubOf(deps, adventurerId),
    gateSource(deps, START_GATE),
  ]);
  if (here !== source) await run(deps, "travel", [call(deps.hub, "travel", id, BigInt(source))]);
  await run(deps, "set_build", [call(deps.hub, "set_build", id, EMPTY_BUILD, 0n, 0n)]);
  await run(deps, "enter", [call(deps.hub, "enter", id, BigInt(START_GATE))]);
}

/**
 * The burner's player, restored from the views or made: (1) no account, `register` and
 * `create_adventurer` in one execution; (2) an account with no adventurer, `create_adventurer`
 * alone; (3) an adventurer inside an instance is played, nothing sent; (4) otherwise it enters.
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
  if (!placement.inside) {
    await enter(deps, adventurerId);
    placement = await deps.reader.placement(deps.instances, adventurerId);
    if (!placement.inside) throw new SetupFailed("enter", "unknown");
  }
  return { address, adventurerId, instanceId: placement.instanceId, member: placement.member };
}
