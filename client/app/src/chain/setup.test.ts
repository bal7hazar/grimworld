import { hash, shortString } from "starknet";
import { describe, expect, it } from "vitest";
import {
  AccountError,
  type AccountProvider,
  type Call,
  type ExecutionId,
  type ExecutionStatus,
} from "../account";
import {
  BURNER_NAME,
  type Build,
  EMPTY_BUILD,
  type Kit,
  START_GATE,
  SetupFailed,
  type SetupDeps,
  beltWord,
  buildWord,
  enter,
  hubSelector,
  restore,
} from "./setup";

const HUB = "0x13";
const INSTANCES = "0x14";
const REGISTRY = "0x11";
const ADDRESS = "0xb0";
/** Gate 1's source in this fake world: the start hub. */
const START_HUB = 7;
const ADMIN = "0xa0";
const FATE = "0x12";
const FLATTEN = "0xf1";
/** SEED-02's build as `devnet_deploy.py --build full` writes it: four skills, two heals, item 23. */
const BUILD: Build = {
  bar: [1, 2, 3, 4, 0, 0, 0, 0],
  belt: [
    { item: 1, count: 2 },
    { item: 23, count: 1 },
  ],
  gold: 260n,
};
/** D-277's trainer prices, a first skill to a fourth. */
const PRICES = [50n, 60n, 70n, 80n];

interface World {
  /** 0: no account. */
  accountId: number;
  adventurers: number[];
  /** The hub the adventurer stands in; 0 inside an instance. */
  hub: number;
  inside: boolean;
  instance: bigint;
  /** Whether a snapshot was set since the last entry (`enter` refuses without one). */
  built: boolean;
  /** The status the next execution ends on. */
  next: ExecutionStatus;
  /** The build word and belt word of the last `set_build`. */
  snapshot: [bigint, bigint];
  /** Skills bought at the trainer, the pack's gold and its balances by item. */
  known: Set<number>;
  gold: bigint;
  pack: Map<number, number>;
  /** `Hub.instances`. */
  instances: string;
  /** The status the next execution of the administrator ends on. */
  adminNext: ExecutionStatus;
}

/**
 * The Hub and Instances as the setup sees them: views read, executions applied in order, as the
 * contracts do (`enter` needs a fresh snapshot and the gate's hub).
 */
function fakeChain(start: Partial<World> = {}, withKit = false) {
  const world: World = {
    accountId: 0,
    adventurers: [],
    hub: START_HUB,
    inside: false,
    instance: 0n,
    built: false,
    next: "succeeded",
    snapshot: [0n, 0n],
    known: new Set(),
    gold: 0n,
    pack: new Map(),
    instances: INSTANCES,
    adminNext: "succeeded",
    ...start,
  };
  const sent: string[][] = [];
  /** The administrator's executions, apart. */
  const admin: string[][] = [];
  let entered = 0n;
  const belt = (word: bigint) =>
    [0, 1, 2, 3]
      .map((lane) => ({
        item: Number((word >> BigInt(32 * lane)) & 0xffffffffn),
        count: Number((word >> BigInt(128 + 8 * lane)) & 0xffn),
      }))
      .filter(({ count }) => count > 0);
  /** What the Hub refuses before any write: the fee estimate reverts, and `execute` rejects. */
  const refuses = (call: Call): boolean => {
    const args = call.calldata.map(BigInt);
    if (call.entrypoint === "set_build") {
      const bar = [0, 1, 2, 3, 4, 5, 6, 7].map((slot) =>
        Number((args[1]! >> BigInt(16 * slot)) & 0xffffn),
      );
      if (bar.some((skill) => skill !== 0 && !world.known.has(skill))) return true;
      return belt(args[2]!).some(({ item, count }) => (world.pack.get(item) ?? 0) < count);
    }
    if (call.entrypoint === "buy_skill") {
      return world.known.has(Number(args[1])) || world.gold < PRICES[world.known.size]!;
    }
    return false;
  };
  const apply = (call: Call) => {
    const args = call.calldata.map(BigInt);
    switch (call.entrypoint) {
      case "register":
        world.accountId = 1;
        return;
      case "create_adventurer":
        expect(args).toEqual([BURNER_NAME, 1n]);
        world.adventurers.push(2);
        return;
      case "travel":
        world.hub = Number(args[1]);
        return;
      case "set_build":
        expect(args[0]).toBe(2n);
        if (!kit) expect(args).toEqual([2n, EMPTY_BUILD, 0n, 0n]);
        world.built = true;
        world.snapshot = [args[1]!, args[2]!];
        return;
      case "enter":
        expect(args).toEqual([2n, BigInt(START_GATE)]);
        if (!world.built || world.hub !== START_HUB) throw new Error("enter refused");
        // The entry debits the belt from the pack
        for (const { item, count } of belt(world.snapshot[1])) {
          world.pack.set(item, world.pack.get(item)! - count);
        }
        world.inside = true;
        world.hub = 0;
        world.built = false;
        world.instance = (++entered << 32n) | 1n;
        return;
      case "buy_skill":
        world.gold -= PRICES[world.known.size]!;
        world.known.add(Number(args[1]));
        return;
      case "travel_back":
        expect(call.to).toBe(INSTANCES);
        expect(args).toEqual([world.instance, 2n, 0n]);
        world.inside = false;
        world.hub = START_HUB;
        return;
      default:
        throw new Error(`unexpected ${call.entrypoint}`);
    }
  };
  const statuses = new Map<string, ExecutionStatus>();
  const provider: AccountProvider = {
    createOrRestore: async () => ({ address: ADDRESS }),
    async execute(calls) {
      sent.push(calls.map((c) => c.entrypoint));
      expect(calls.every((c) => c.to === (c.entrypoint === "travel_back" ? INSTANCES : HUB))).toBe(
        true,
      );
      if (calls.some(refuses)) throw new AccountError("refused");
      const status = world.next;
      world.next = "succeeded";
      if (status === "succeeded") calls.forEach(apply);
      const id = `0x${sent.length}`;
      statuses.set(id, status);
      return id as ExecutionId;
    },
    status: async (id) => statuses.get(id) ?? "unknown",
    signOut: async () => undefined,
  };
  const reader: SetupDeps["reader"] = {
    async call(to, entry, calldata) {
      expect(to).toBe(HUB);
      if (entry === hubSelector.account_of) {
        expect(calldata).toEqual([BigInt(ADDRESS)]);
        return [BigInt(world.accountId)];
      }
      if (entry === hubSelector.account) {
        const ids = world.adventurers.map(BigInt);
        return [BigInt(ADDRESS), 0x99n, BigInt(ids.length), ...ids];
      }
      if (entry === hubSelector.adventurer) {
        // The place word: hub at bits 64-79, last hub at 80-95, the instance at 0-63
        const place = (BigInt(world.hub) << 64n) | (BigInt(START_HUB) << 80n) | world.instance;
        return [6n, 0x5n, place, 0n, 0n, 0n, 0x4275726e6572n];
      }
      throw new Error("unexpected view");
    },
    async record(registry, kind, id) {
      expect([registry, kind, id]).toEqual([REGISTRY, 4, START_GATE]);
      // source 7, destination 3 at bits 16-31
      return [BigInt(START_HUB) | (3n << 16n), 0n];
    },
    async placement(instances, adventurerId) {
      expect([instances, adventurerId]).toEqual([INSTANCES, 2]);
      return { instanceId: world.instance, member: 0, inside: world.inside };
    },
    async instanceState(instances, instanceId) {
      expect([instances, instanceId]).toEqual([INSTANCES, world.instance]);
      return { header: { sequence: 0 } } as Awaited<
        ReturnType<SetupDeps["reader"]["instanceState"]>
      >;
    },
  };
  /** The Hub's administrator: `set_contracts`, and `report` while `Hub.instances` is itself. */
  const adminStatuses = new Map<string, ExecutionStatus>();
  const kit: Kit | undefined = withKit
    ? {
        build: BUILD,
        fate: FATE,
        flatten: FLATTEN,
        hubInstances: async () => BigInt(world.instances),
        admin: {
          address: ADMIN,
          async execute(calls) {
            admin.push(calls.map((c) => c.entrypoint));
            const [call] = calls;
            const args = call!.calldata.map(BigInt);
            let status = world.adminNext;
            world.adminNext = "succeeded";
            if (call!.entrypoint === "set_contracts") {
              expect(args).toEqual([BigInt(REGISTRY), args[1], 4n, BigInt(FATE), BigInt(FLATTEN)]);
              if (status === "succeeded") world.instances = `0x${args[1]!.toString(16)}`;
            } else {
              expect(call!.entrypoint).toBe("report");
              if (world.instances !== ADMIN || !world.inside) status = "failed";
              if (status === "succeeded") {
                // instance, [adventurer], experience, gold, balances..., Open
                expect(args.slice(0, 5)).toEqual([world.instance, 1n, 2n, 0n, BUILD.gold]);
                expect(args.slice(5, 10)).toEqual([2n, 1n, 4n, 23n, 2n]);
                // No equipment, task, fact or location; Open; no hub, next instance or belt
                expect(args.slice(10)).toEqual(Array(11).fill(0n));
                world.gold += BUILD.gold;
                world.pack.set(1, (world.pack.get(1) ?? 0) + 4);
                world.pack.set(23, (world.pack.get(23) ?? 0) + 2);
              }
            }
            const id = `0xa${admin.length}`;
            adminStatuses.set(id, status);
            return id as ExecutionId;
          },
          status: async (id) => adminStatuses.get(id) ?? "unknown",
        },
      }
    : undefined;
  const deps: SetupDeps = {
    provider,
    reader,
    hub: HUB,
    instances: INSTANCES,
    registry: REGISTRY,
    pollMs: 0,
    ...(kit ? { kit } : {}),
  };
  return { world, sent, admin, deps };
}

describe("selectors and constants", () => {
  it("are sn_keccak of the Hub's view names", () => {
    for (const [name, value] of Object.entries(hubSelector)) {
      expect(BigInt(hash.getSelectorFromName(name)), name).toBe(value);
    }
  });

  it("name the adventurer 'Burner', and build an empty bar as devnet_deploy.py does", () => {
    expect(BURNER_NAME).toBe(BigInt(shortString.encodeShortString("Burner")));
    expect(EMPTY_BUILD).toBe(255n << 168n);
  });
});

describe("restore (§3.4)", () => {
  it("with no account: register and create in one execution, then set_build, then enter", async () => {
    const { sent, deps, world } = fakeChain();
    const player = await restore(deps);
    expect(sent).toEqual([["register", "create_adventurer"], ["set_build"], ["enter"]]);
    expect(player).toEqual({
      address: ADDRESS,
      adventurerId: 2,
      instanceId: world.instance,
      member: 0,
    });
    expect(world.inside).toBe(true);
  });

  it("with an account and no adventurer (stopped after register): create alone, then enter", async () => {
    const { sent, deps } = fakeChain({ accountId: 1 });
    await restore(deps);
    expect(sent).toEqual([["create_adventurer"], ["set_build"], ["enter"]]);
  });

  it("with an adventurer stopped after create_adventurer: set_build, then enter", async () => {
    const { sent, deps } = fakeChain({ accountId: 1, adventurers: [2] });
    await restore(deps);
    expect(sent).toEqual([["set_build"], ["enter"]]);
  });

  it("with an adventurer stopped after set_build: set_build again, then enter", async () => {
    const { sent, deps } = fakeChain({ accountId: 1, adventurers: [2], built: true });
    await restore(deps);
    expect(sent).toEqual([["set_build"], ["enter"]]);
  });

  it("with an adventurer inside an instance: that instance, nothing sent", async () => {
    const instance = (5n << 32n) | 1n;
    const { sent, deps } = fakeChain({
      accountId: 1,
      adventurers: [2],
      inside: true,
      hub: 0,
      instance,
    });
    expect(await restore(deps)).toMatchObject({ adventurerId: 2, instanceId: instance });
    expect(sent).toEqual([]);
  });

  it("with an adventurer back in another hub: travel to the gate's hub first", async () => {
    const { sent, deps, world } = fakeChain({ accountId: 1, adventurers: [2], hub: 9 });
    await restore(deps);
    expect(sent).toEqual([["travel"], ["set_build"], ["enter"]]);
    expect(world.inside).toBe(true);
  });

  it("stops on a failed step, and the next pass resumes from the views", async () => {
    const { sent, deps, world } = fakeChain({ accountId: 1, adventurers: [2] });
    world.next = "failed";
    await expect(restore(deps)).rejects.toEqual(new SetupFailed("set_build", "failed"));
    expect(sent).toEqual([["set_build"]]);
    await restore(deps);
    expect(sent).toEqual([["set_build"], ["set_build"], ["enter"]]);
  });

  it("restores the same adventurer and instance on a second pass, without registering again", async () => {
    const { sent, deps } = fakeChain();
    const first = await restore(deps);
    const count = sent.length;
    expect(await restore(deps)).toEqual(first);
    expect(sent).toHaveLength(count);
  });
});

describe("enter (§3.4, after a closing)", () => {
  it("enters the same adventurer again: set_build then enter, no travel, no new adventurer", async () => {
    const { sent, deps, world } = fakeChain();
    const first = await restore(deps);
    // The instance closes: `Hub.report` returns the adventurer to its last hub, the start hub
    Object.assign(world, { inside: false, hub: START_HUB });
    sent.length = 0;
    await enter(deps, first.adventurerId);
    expect(sent).toEqual([["set_build"], ["enter"]]);
    const again = await restore(deps);
    expect(again.adventurerId).toBe(first.adventurerId);
    expect(again.instanceId).not.toBe(first.instanceId);
    expect(world.adventurers).toEqual([2]);
  });
});

describe("the burner's build on devnet (CLI-11d2)", () => {
  it("encodes the bar and the belt as devnet_deploy.py's build_word and belt_word", () => {
    // `build_word([3, 7, 11, 23, 0, 0, 0, 0])` and `belt_word([(1, 2), (23, 1)])`
    expect(buildWord([3, 7, 11, 23, 0, 0, 0, 0])).toBe(
      0xff000000000000000000000000000017000b00070003n,
    );
    expect(beltWord(BUILD.belt)).toBe(0x10200000000000000000000001700000001n);
    expect(buildWord(Array(8).fill(0))).toBe(EMPTY_BUILD);
  });

  it("a new burner: set_build refused, the harness funds, the four skills bought, then built", async () => {
    const { sent, admin, deps, world } = fakeChain({}, true);
    const player = await restore(deps);
    expect(sent).toEqual([
      ["register", "create_adventurer"],
      ["set_build"], // refused: no skill known, an empty pack
      ["set_build"], // the harness's entry, with the empty bar
      ["enter"],
      ["travel_back"],
      ["buy_skill"],
      ["buy_skill"],
      ["buy_skill"],
      ["buy_skill"],
      ["set_build"],
      ["enter"],
    ]);
    expect(admin).toEqual([["set_contracts"], ["report"], ["set_contracts"]]);
    expect(world.instances).toBe(INSTANCES);
    expect([...world.known]).toEqual([1, 2, 3, 4]);
    expect(world.gold).toBe(0n);
    expect(world.snapshot).toEqual([buildWord(BUILD.bar), beltWord(BUILD.belt)]);
    // Twice the belt credited, the belt debited at entry: one more entry is covered
    expect(Object.fromEntries(world.pack)).toEqual({ 1: 2, 23: 1 });
    expect(player).toMatchObject({ adventurerId: 2, instanceId: world.instance });
    expect(world.inside).toBe(true);
  });

  it("enters again with the build alone while the pack covers the belt", async () => {
    const { sent, admin, deps, world } = fakeChain({}, true);
    await restore(deps);
    // The instance closes: the unused belt is credited back, the adventurer is in the start hub
    Object.assign(world, { inside: false, hub: START_HUB });
    world.pack.set(1, 4).set(23, 2);
    sent.length = admin.length = 0;
    await enter(deps, 2);
    expect(sent).toEqual([["set_build"], ["enter"]]);
    expect(admin).toEqual([]);
  });

  it("funds again when the potions were drunk; the known skills are refused, and skipped", async () => {
    const { sent, admin, deps, world } = fakeChain({}, true);
    await restore(deps);
    Object.assign(world, { inside: false, hub: START_HUB });
    world.pack.set(1, 0).set(23, 0);
    sent.length = admin.length = 0;
    await enter(deps, 2);
    expect(sent).toEqual([
      ["set_build"],
      ["set_build"],
      ["enter"],
      ["travel_back"],
      ["buy_skill"],
      ["buy_skill"],
      ["buy_skill"],
      ["buy_skill"],
      ["set_build"],
      ["enter"],
    ]);
    expect(admin).toEqual([["set_contracts"], ["report"], ["set_contracts"]]);
    expect([...world.known]).toEqual([1, 2, 3, 4]);
    // The gold of the second funding is left: every skill was known
    expect(world.gold).toBe(BUILD.gold);
    expect(world.inside).toBe(true);
  });

  it("restores Hub.instances when the report fails, and stops on the report", async () => {
    const { sent, admin, deps, world } = fakeChain({ accountId: 1, adventurers: [2] }, true);
    const report = deps.kit!.admin.execute.bind(deps.kit!.admin);
    let reports = 0;
    const failing = {
      ...deps.kit!.admin,
      execute: (calls: readonly Call[]) => {
        if (calls[0]!.entrypoint === "report" && reports++ === 0) world.adminNext = "failed";
        return report(calls);
      },
    };
    const kit = { ...deps.kit!, admin: failing };
    await expect(restore({ ...deps, kit })).rejects.toEqual(new SetupFailed("report", "failed"));
    expect(admin).toEqual([["set_contracts"], ["report"], ["set_contracts"]]);
    expect(world.instances).toBe(INSTANCES);
    // The adventurer is left in the harness's instance, with the empty bar: the next pass plays it
    expect(sent).toEqual([["set_build"], ["set_build"], ["enter"]]);
    expect(world.inside).toBe(true);
  });

  it("stops when Hub.instances does not read back as Instances", async () => {
    const { deps, world } = fakeChain({ accountId: 1, adventurers: [2] }, true);
    const kit = { ...deps.kit!, hubInstances: async () => BigInt(ADMIN) };
    await expect(restore({ ...deps, kit })).rejects.toEqual(new SetupFailed("harness", "unknown"));
    expect(world.known.size).toBe(0);
  });

  it("without a kit, the empty bar: no buy_skill, no harness", async () => {
    const { sent, admin, deps } = fakeChain();
    await restore(deps);
    expect(sent.flat()).not.toContain("buy_skill");
    expect(admin).toEqual([]);
  });
});
