import { AccountError, type AccountProvider, type Call, type ExecutionStatus } from "../account";
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
/** The deployment's own account, the Hub's administrator: the devnet harness only (D-280). */
export const ADMIN_INDEX = 0;
/** STRK given to each new burner: 100 STRK, in fri. */
export const BURNER_FUNDS = 10n ** 20n;
/** An empty bar (elite slot 255 at bit 168), as `scripts/devnet_deploy.py` sets it. */
export const EMPTY_BUILD = 255n << 168n;
export const BAR_SLOTS = 8;
export const BELT_SLOTS = 4;
/** `Hub.set_contracts`'s market, as `devnet_deploy.py` passes it. */
const MARKET = 4n;
/** `Outcome::Open`: a report that keeps the adventurer inside. */
const OPEN = 0n;
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

/** The deployment's `--build full` (OPS-01b, SEED-02): skill ids by bar slot, the belt, the gold. */
export interface Build {
  readonly bar: readonly number[];
  readonly belt: readonly { readonly item: number; readonly count: number }[];
  /** What the four skills cost at the trainer (D-277), credited by the harness. */
  readonly gold: bigint;
}

/** An account that sends executions: the burner's provider, or the harness's administrator. */
export type Sender = Pick<AccountProvider, "execute" | "status"> & { readonly address: string };

/**
 * The burner's build on devnet (CLI-11d2), and the harness that pays for it as
 * `scripts/devnet_deploy.py`'s `fund_pack` does (D-280, devnet only): no entrypoint credits gold or
 * fills a pack yet but `Hub.report`, so the Hub's administrator points `Hub.instances` at itself for
 * one Open report, then back. `network.ts` builds it only for a `--build full` deployment on the
 * local node.
 */
export interface Kit {
  readonly build: Build;
  readonly admin: Sender;
  readonly fate: string;
  readonly flatten: string;
  /** `Hub.instances` as the chain stores it (no view returns it). */
  hubInstances(): Promise<bigint>;
}

/** `set_build`'s `Build` word without `LIVE`: 16 bits a slot, the elite slot empty. */
export function buildWord(bar: readonly number[]): bigint {
  return bar.reduce(
    (word, skill, slot) => word | (BigInt(skill) << BigInt(16 * slot)),
    EMPTY_BUILD,
  );
}

/** `set_build`'s belt word: the items in lanes 0-3 (32 bits), their counts at bit 128 (8 bits). */
export function beltWord(belt: Build["belt"]): bigint {
  return belt.reduce(
    (word, { item, count }, lane) =>
      word | (BigInt(item) << BigInt(32 * lane)) | (BigInt(count) << BigInt(128 + 8 * lane)),
    0n,
  );
}

export interface SetupDeps {
  readonly provider: AccountProvider;
  readonly reader: Pick<Reader, "call" | "placement" | "record" | "instanceState">;
  readonly hub: string;
  readonly instances: string;
  readonly registry: string;
  /** Between two asks of an execution's status, in ms. */
  readonly pollMs?: number;
  /** The burner's build and its harness; without it, the empty bar. */
  readonly kit?: Kit;
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

/**
 * Sends one execution and waits until it settles; anything but `succeeded` is `SetupFailed`. The
 * burner sends, or `from`.
 */
async function run(
  deps: SetupDeps,
  step: string,
  calls: Call[],
  from: Pick<AccountProvider, "execute" | "status"> = deps.provider,
): Promise<void> {
  const id = await from.execute(calls);
  const pollMs = deps.pollMs ?? 250;
  for (;;) {
    const status = await from.status(id);
    if (status === "succeeded") return;
    if (status !== "pending") throw new SetupFailed(step, status);
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
}

/**
 * `run`, where a refusal is an answer: false when the node refuses the execution before it is sent
 * (its fee estimate reverts) or it fails. Anything else, a refused chain included, throws.
 */
async function attempt(deps: SetupDeps, step: string, calls: Call[]): Promise<boolean> {
  try {
    await run(deps, step, calls);
    return true;
  } catch (error) {
    if (error instanceof SetupFailed && error.status === "failed") return false;
    if (error instanceof AccountError && error.code === "refused") return false;
    throw error;
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
 * The harness (D-280), as `devnet_deploy.py`'s `fund_pack`: the adventurer, in gate 1's hub, enters
 * with the empty bar; the administrator points `Hub.instances` at itself and sends one Open report
 * that credits the gold and twice the belt to the pack, then points it back and reads it back (after
 * a failed report too); the adventurer travels back to the start hub.
 */
async function fund(deps: SetupDeps, kit: Kit, adventurerId: number): Promise<void> {
  const id = BigInt(adventurerId);
  await run(deps, "set_build", [call(deps.hub, "set_build", id, EMPTY_BUILD, 0n, 0n)]);
  await run(deps, "enter", [call(deps.hub, "enter", id, BigInt(START_GATE))]);
  const { inside, instanceId } = await deps.reader.placement(deps.instances, adventurerId);
  if (!inside) throw new SetupFailed("enter", "unknown");
  const contracts = (instances: string) =>
    call(
      deps.hub,
      "set_contracts",
      BigInt(deps.registry),
      BigInt(instances),
      MARKET,
      BigInt(kit.fate),
      BigInt(kit.flatten),
    );
  const credits = kit.build.belt.flatMap(({ item, count }) => [BigInt(item), 2n * BigInt(count)]);
  // `Results`: the instance, one contributor, no experience, the gold, the balances; no equipment,
  // task, fact or location; Open, so no hub, next instance or belt
  const report = call(
    deps.hub,
    "report",
    instanceId,
    1n,
    id,
    0n,
    kit.build.gold,
    BigInt(kit.build.belt.length),
    ...credits,
    0n,
    0n,
    0n,
    0n,
    OPEN,
    0n,
    0n,
    0n,
    0n,
    0n,
    0n,
  );
  await run(deps, "harness", [contracts(kit.admin.address)], kit.admin);
  const failed = await run(deps, "report", [report], kit.admin).then(
    () => undefined,
    (error: unknown) => ({ error }),
  );
  // Restored and read back whether the report passed or not; its failure is thrown after
  await run(deps, "harness", [contracts(deps.instances)], kit.admin);
  if ((await kit.hubInstances()) !== BigInt(deps.instances)) {
    throw new SetupFailed("harness", "unknown");
  }
  if (failed !== undefined) throw failed.error;
  const { header } = await deps.reader.instanceState(deps.instances, instanceId);
  await run(deps, "travel_back", [
    call(deps.instances, "travel_back", instanceId, id, BigInt(header.sequence)),
  ]);
}

/**
 * Step 4 of §3.4: the adventurer, in a hub, enters gate `START_GATE`. `Hub.travel` first only when
 * its hub is not the gate's source; `Hub.set_build` before every `enter` (the views cannot show
 * whether an earlier one ran, and it overwrites); `Hub.enter` alone, because the entry draws Fate.
 * This is also what `N` runs after an instance closes.
 *
 * With a kit (CLI-11d2), `set_build` carries the deployment's build, and its refusal is the probe:
 * no view reads the known skills or the pack yet, and `set_build` refuses a bar skill not known or
 * a belt the pack does not cover. Refused, the harness funds the pack and the gold (`fund`), each
 * skill of the bar is bought (a known one is refused, and skipped), and `set_build` is sent again,
 * now required to pass.
 */
export async function enter(deps: SetupDeps, adventurerId: number): Promise<void> {
  const id = BigInt(adventurerId);
  const [here, source] = await Promise.all([
    hubOf(deps, adventurerId),
    gateSource(deps, START_GATE),
  ]);
  if (here !== source) await run(deps, "travel", [call(deps.hub, "travel", id, BigInt(source))]);
  const { kit } = deps;
  if (kit === undefined) {
    await run(deps, "set_build", [call(deps.hub, "set_build", id, EMPTY_BUILD, 0n, 0n)]);
  } else {
    const { bar, belt } = kit.build;
    const built = [call(deps.hub, "set_build", id, buildWord(bar), beltWord(belt), 0n)];
    if (!(await attempt(deps, "set_build", built))) {
      await fund(deps, kit, adventurerId);
      for (const skill of bar.filter((skill) => skill !== 0)) {
        await attempt(deps, "buy_skill", [call(deps.hub, "buy_skill", id, BigInt(skill))]);
      }
      await run(deps, "set_build", built);
    }
  }
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
