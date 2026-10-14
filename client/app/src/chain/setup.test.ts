import { RpcError, hash, shortString } from "starknet";
import { describe, expect, it } from "vitest";
import {
  AccountError,
  type AccountProvider,
  type Call,
  type ExecutionId,
  type ExecutionStatus,
} from "../account";
import type { InstanceView } from "../preview";
import type { Credit, CreditStatus } from "./credit";
import { ChainRefused } from "./network";
import {
  BACK_GATE,
  BURNER_NAME,
  type Build,
  EMPTY_BUILD,
  LIVE,
  START_GATE,
  SetupFailed,
  type SetupDeps,
  beltWord,
  buildWord,
  builtWith,
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
/** SEED-02's build as `devnet_deploy.py --build full` writes it. */
const BUILD: Build = {
  bar: [1, 2, 3, 4, 0, 0, 0, 0],
  belt: [
    { item: 1, count: 2 },
    { item: 23, count: 1 },
  ],
};
/** D-277's four trainer prices. */
const GOLD = 260;

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
  /** An error the next execution throws instead of running (consumed), as the account module wraps it. */
  rejectWith?: unknown;
  /** The `Build` and belt words of the last `set_build`, without `LIVE`. */
  build: bigint;
  belt: bigint;
  known: number[];
  gold: number;
  /** The pack, by item. */
  pack: Record<number, number>;
  /** The instance's sequence, and whether the member still stands on gate 2's anchor. */
  sequence: number;
  onAnchor: boolean;
  /** Credits started (`Credit.status`). */
  credits: number;
}

/** The `RpcError` a node answers with, for a spec error code. */
const rpcError = (code: number) =>
  new RpcError({ code, message: `error ${code}` } as never, "starknet_estimateFee", {});

/** The belt's `(item, count)` lanes from its word. */
const lanesOf = (belt: bigint): [number, number][] =>
  [0, 1, 2, 3]
    .map((lane): [number, number] => [
      Number((belt >> BigInt(32 * lane)) & 0xffffffffn),
      Number((belt >> (128n + BigInt(8 * lane))) & 0xffn),
    ])
    .filter(([item]) => item !== 0);

/**
 * The Hub and Instances as the setup sees them: views read, executions applied in order, as the
 * contracts do (`enter` needs a fresh snapshot and the gate's hub).
 */
function fakeChain(start: Partial<World> = {}) {
  const world: World = {
    accountId: 0,
    adventurers: [],
    hub: START_HUB,
    inside: false,
    instance: 0n,
    built: false,
    next: "succeeded",
    build: EMPTY_BUILD,
    belt: 0n,
    known: [],
    gold: 0,
    pack: {},
    sequence: 0,
    onAnchor: true,
    credits: 0,
    ...start,
  };
  const sent: string[][] = [];
  let entered = 0n;
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
      case "set_build": {
        expect(args[0]).toBe(2n);
        expect(args[3]).toBe(0n);
        const [, build, belt] = args as [bigint, bigint, bigint];
        if (world.hub === 0) throw new Error("NOT_IN_HUB");
        // The bar's skills are known, and the pack covers the belt (`assert_held`)
        for (let slot = 0; slot < 8; slot++) {
          const skill = Number((build >> BigInt(16 * slot)) & 0xffffn);
          if (skill !== 0 && !world.known.includes(skill)) throw new Error("skill: unknown");
        }
        for (const [item, count] of lanesOf(belt)) {
          if ((world.pack[item] ?? 0) < count) throw new Error("balance: not enough");
        }
        Object.assign(world, { build, belt, built: true });
        return;
      }
      case "enter":
        expect(args).toEqual([2n, BigInt(START_GATE)]);
        if (!world.built || world.hub !== START_HUB) throw new Error("enter refused");
        // The belt's reserve is debited from the pack
        for (const [item, count] of lanesOf(world.belt)) world.pack[item]! -= count;
        world.inside = true;
        world.hub = 0;
        world.built = false;
        world.sequence = 0;
        world.onAnchor = true;
        world.instance = (++entered << 32n) | 1n;
        return;
      case "leave":
        expect(call.to).toBe(INSTANCES);
        expect(args).toEqual([world.instance, 2n, BigInt(world.sequence), BigInt(BACK_GATE)]);
        // A refused leave returns without a revert: the adventurer stays inside
        if (!world.inside || !world.onAnchor) return;
        Object.assign(world, { inside: false, hub: START_HUB });
        return;
      case "buy_skill": {
        const skill = Number(args[1]);
        if (world.hub === 0) throw new Error("NOT_IN_HUB");
        if (world.known.includes(skill)) throw new Error("skill: known");
        const price = [50, 60, 70, 80][world.known.length]!;
        if (world.gold < price) throw new Error("gold: not enough");
        world.gold -= price;
        world.known.push(skill);
        return;
      }
      default:
        throw new Error(`unexpected ${call.entrypoint}`);
    }
  };
  const statuses = new Map<string, ExecutionStatus>();
  const provider: AccountProvider = {
    createOrRestore: async () => ({ address: ADDRESS }),
    async execute(calls) {
      sent.push(calls.map((c) => c.entrypoint));
      if (world.rejectWith !== undefined) {
        const cause = world.rejectWith;
        world.rejectWith = undefined;
        throw new AccountError("refused", { cause });
      }
      expect(calls.every((c) => c.to === (c.entrypoint === "leave" ? INSTANCES : HUB))).toBe(true);
      const status = world.next;
      world.next = "succeeded";
      if (status === "succeeded") {
        // One execution is all or nothing: a call that reverts is the fee estimate's refusal
        const before = structuredClone(world);
        try {
          calls.forEach(apply);
        } catch (error) {
          Object.assign(world, before);
          // A call that reverts while the fee is estimated: TRANSACTION_EXECUTION_ERROR (41)
          throw new AccountError("refused", { cause: Object.assign(rpcError(41), { error }) });
        }
      }
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
        return [6n, 0x5n, place, world.build + LIVE, world.belt + LIVE, LIVE, 0x4275726e6572n];
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
      return { header: { sequence: world.sequence } } as unknown as InstanceView;
    },
  };
  /** The development server's credit, as `--credit-only` does it: 260 gold, twice the belt. */
  let state: CreditStatus["state"] = "idle";
  const credited: number[] = [];
  const credit: Credit & { state: (next: CreditStatus["state"]) => void } = {
    async credit(adventurerId) {
      expect(adventurerId).toBe(2);
      if (!world.inside) throw new Error("not inside an instance");
      world.credits += 1;
      credited.push(adventurerId);
      world.gold += GOLD;
      for (const { item, count } of BUILD.belt)
        world.pack[item] = (world.pack[item] ?? 0) + 2 * count;
    },
    status: async () => ({ state, credits: world.credits }),
    async assertUsable() {
      if (state === "unusable") throw new ChainRefused("devnet left mid-credit: redeploy");
    },
    state: (next) => void (state = next),
  };
  const deps: SetupDeps = {
    provider,
    reader,
    hub: HUB,
    instances: INSTANCES,
    registry: REGISTRY,
    pollMs: 0,
  };
  const built: SetupDeps = { ...deps, build: BUILD, credit };
  return { world, sent, deps, built, credit, credited };
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

describe("the deployment's build (CLI-11d3)", () => {
  const FULL = buildWord(BUILD.bar);
  const BELT = beltWord(BUILD.belt);
  const BUILD_STEP = ["leave", "buy_skill", "buy_skill", "buy_skill", "buy_skill", "set_build"];

  it("encodes the build and the belt as devnet_deploy.py's build_word and belt_word", () => {
    expect(FULL).toBe(1n + (2n << 16n) + (3n << 32n) + (4n << 48n) + EMPTY_BUILD);
    expect(BELT).toBe(1n + (23n << 32n) + ((2n + (1n << 8n)) << 128n));
    expect(buildWord([0, 0, 0, 0, 0, 0, 0, 0])).toBe(EMPTY_BUILD);
    expect(beltWord([])).toBe(0n);
  });

  it("first entry: built empty and entered, credited, then leave, buy the skills and set the build in one execution, and enter", async () => {
    const { sent, built, world, credited } = fakeChain();
    const player = await restore(built);
    expect(sent).toEqual([
      ["register", "create_adventurer"],
      ["set_build"],
      ["enter"],
      BUILD_STEP,
      ["enter"],
    ]);
    expect(credited).toEqual([2]);
    expect(world).toMatchObject({ inside: true, build: FULL, belt: BELT, known: [1, 2, 3, 4] });
    // 260 gold spent on the four skills; the entry took the belt from the pack of twice the belt
    expect(world.gold).toBe(0);
    expect(world.pack).toEqual({ 1: 2, 23: 1 });
    expect(player).toEqual({
      address: ADDRESS,
      adventurerId: 2,
      instanceId: world.instance,
      member: 0,
    });
    expect(await builtWith(built, 2, BUILD)).toBe(true);
  });

  it("built and inside: nothing sent, no credit", async () => {
    const { sent, built, credited } = fakeChain();
    const first = await restore(built);
    sent.length = 0;
    expect(await restore(built)).toEqual(first);
    expect(sent).toEqual([]);
    expect(credited).toEqual([2]);
  });

  it("re-entry after a closing (N): the build with its belt, then enter; no credit, no skill bought", async () => {
    const { sent, built, world, credited } = fakeChain();
    await restore(built);
    // The instance closes: the unused belt goes back to the pack, the adventurer to the start hub
    Object.assign(world, { inside: false, hub: START_HUB, pack: { 1: 4, 23: 2 } });
    sent.length = 0;
    await enter(built, 2);
    expect(sent).toEqual([["set_build"], ["enter"]]);
    expect(world).toMatchObject({ inside: true, build: FULL, belt: BELT });
    expect(credited).toEqual([2]);
  });

  it("re-entry with the potions spent: the build's set_build is refused, so the bar with an empty belt", async () => {
    const { sent, built, world } = fakeChain();
    await restore(built);
    Object.assign(world, { inside: false, hub: START_HUB, pack: { 1: 1 } });
    sent.length = 0;
    await enter(built, 2);
    expect(sent).toEqual([["set_build"], ["set_build"], ["enter"]]);
    expect(world).toMatchObject({ inside: true, build: FULL, belt: 0n });
  });

  it("re-entry whose full set_build executes and fails: the bar with an empty belt", async () => {
    const { sent, built, world } = fakeChain();
    await restore(built);
    Object.assign(world, { inside: false, hub: START_HUB, next: "failed" });
    sent.length = 0;
    await enter(built, 2);
    expect(sent).toEqual([["set_build"], ["set_build"], ["enter"]]);
    expect(world).toMatchObject({ inside: true, build: FULL, belt: 0n });
  });

  it("re-entry whose estimate is refused with an execution error code (40, 41): the bar with an empty belt", async () => {
    for (const code of [40, 41]) {
      const { sent, built, world } = fakeChain();
      await restore(built);
      Object.assign(world, { inside: false, hub: START_HUB, rejectWith: rpcError(code) });
      sent.length = 0;
      await enter(built, 2);
      expect(sent).toEqual([["set_build"], ["set_build"], ["enter"]]);
      expect(world).toMatchObject({ inside: true, build: FULL, belt: 0n });
    }
  });

  it("re-entry whose send fails on a nonce error (52) or a rate limit: an error, no second set_build", async () => {
    for (const code of [52, 54, 63, 100]) {
      const { sent, built, world } = fakeChain();
      await restore(built);
      Object.assign(world, { inside: false, hub: START_HUB, rejectWith: rpcError(code) });
      sent.length = 0;
      await expect(enter(built, 2)).rejects.toMatchObject({
        name: "AccountError",
        code: "refused",
      });
      expect(sent).toEqual([["set_build"]]);
    }
  });

  it("re-entry whose refusal carries no RpcError (a non-Error cause): an error, no fallback", async () => {
    for (const cause of [new Error("boom"), undefined]) {
      const { sent, built, world } = fakeChain();
      await restore(built);
      Object.assign(world, { inside: false, hub: START_HUB, rejectWith: cause ?? "none" });
      sent.length = 0;
      await expect(enter(built, 2)).rejects.toMatchObject({
        name: "AccountError",
        code: "refused",
      });
      expect(sent).toEqual([["set_build"]]);
    }
  });

  it("re-entry whose full set_build ends unknown (a status that never settled): an error, no fallback", async () => {
    const { sent, built, world } = fakeChain();
    await restore(built);
    Object.assign(world, { inside: false, hub: START_HUB, next: "unknown" });
    sent.length = 0;
    await expect(enter(built, 2)).rejects.toMatchObject({ name: "SetupFailed", status: "unknown" });
    expect(sent).toEqual([["set_build"]]);
  });

  it("resumes a setup stopped between its empty entry and its build: credit, build, enter", async () => {
    const { sent, built, world, credited } = fakeChain();
    // Entered built empty (the first pass stopped there), still on gate 2's anchor
    await restore({ ...built, build: undefined });
    sent.length = 0;
    await restore(built);
    expect(credited).toEqual([2]);
    expect(sent).toEqual([BUILD_STEP, ["enter"]]);
    expect(world).toMatchObject({ inside: true, build: FULL, known: [1, 2, 3, 4] });
  });

  it("leaves at the instance's current sequence", async () => {
    const { sent, built, world } = fakeChain();
    await restore({ ...built, build: undefined });
    world.sequence = 3;
    sent.length = 0;
    await restore(built);
    expect(sent[0]).toEqual(BUILD_STEP);
    expect(world.known).toEqual([1, 2, 3, 4]);
  });

  it("a leave the chain refuses (off the gate's anchor) reverts the whole build: nothing bought", async () => {
    const { sent, built, world } = fakeChain();
    await restore({ ...built, build: undefined });
    world.onAnchor = false;
    sent.length = 0;
    await expect(restore(built)).rejects.toBeInstanceOf(AccountError);
    expect(sent).toEqual([BUILD_STEP]);
    expect(world).toMatchObject({ inside: true, known: [], build: EMPTY_BUILD });
  });

  it("without a credit, a build that is not given yet stops at the credit", async () => {
    const { built } = fakeChain();
    await expect(restore({ ...built, credit: undefined })).rejects.toEqual(
      new SetupFailed("credit", "unknown"),
    );
  });

  it("caveat (a): an enter that fails while another credit ran is sent again after it", async () => {
    const { sent, built, world } = fakeChain({ accountId: 1, adventurers: [2] });
    await restore(built);
    Object.assign(world, { inside: false, hub: START_HUB, pack: { 1: 4, 23: 2 } });
    sent.length = 0;
    // Another burner's credit runs during the entry: it reverts, and the count of credits moved
    const execute = built.provider.execute;
    let once = true;
    const during: SetupDeps = {
      ...built,
      provider: {
        ...built.provider,
        async execute(calls) {
          if (once && calls[0]?.entrypoint === "enter") {
            once = false;
            world.credits += 1;
            world.next = "failed";
          }
          return execute(calls);
        },
      },
    };
    await enter(during, 2);
    expect(sent).toEqual([["set_build"], ["enter"], ["enter"]]);
    expect(world.inside).toBe(true);
  });

  it("an enter that fails with no credit in between is a failure", async () => {
    const { built, world } = fakeChain();
    await restore(built);
    Object.assign(world, { inside: false, hub: START_HUB, pack: { 1: 4, 23: 2 } });
    const execute = built.provider.execute;
    const failing: SetupDeps = {
      ...built,
      provider: {
        ...built.provider,
        async execute(calls) {
          if (calls[0]?.entrypoint === "enter") world.next = "failed";
          return execute(calls);
        },
      },
    };
    await expect(enter(failing, 2)).rejects.toEqual(new SetupFailed("enter", "failed"));
  });

  it("waits while a credit runs before it enters", async () => {
    const { sent, built, world, credit } = fakeChain();
    await restore(built);
    Object.assign(world, { inside: false, hub: START_HUB, pack: { 1: 4, 23: 2 } });
    sent.length = 0;
    credit.state("running");
    let polls = 0;
    const status = credit.status;
    const counting: SetupDeps = {
      ...built,
      credit: {
        ...credit,
        async status() {
          if (++polls === 3) credit.state("idle");
          return status();
        },
      },
    };
    await enter(counting, 2);
    expect(polls).toBeGreaterThanOrEqual(3);
    expect(sent).toEqual([["set_build"], ["enter"]]);
  });

  it("caveat (c): a devnet left mid-credit refuses the entry with its line", async () => {
    const { sent, built, world, credit } = fakeChain();
    await restore(built);
    Object.assign(world, { inside: false, hub: START_HUB, pack: { 1: 4, 23: 2 } });
    sent.length = 0;
    credit.state("unusable");
    await expect(enter(built, 2)).rejects.toEqual(
      new ChainRefused("devnet left mid-credit: redeploy"),
    );
    expect(sent).toEqual([["set_build"]]);
  });
});
