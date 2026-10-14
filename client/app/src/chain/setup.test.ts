import { hash, shortString } from "starknet";
import { describe, expect, it } from "vitest";
import type { AccountProvider, Call, ExecutionId, ExecutionStatus } from "../account";
import {
  BURNER_NAME,
  EMPTY_BUILD,
  START_GATE,
  SetupFailed,
  type SetupDeps,
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
}

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
      case "set_build":
        expect(args).toEqual([2n, EMPTY_BUILD, 0n, 0n]);
        world.built = true;
        return;
      case "enter":
        expect(args).toEqual([2n, BigInt(START_GATE)]);
        if (!world.built || world.hub !== START_HUB) throw new Error("enter refused");
        world.inside = true;
        world.hub = 0;
        world.built = false;
        world.instance = (++entered << 32n) | 1n;
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
      expect(calls.every((c) => c.to === HUB)).toBe(true);
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
  };
  const deps: SetupDeps = {
    provider,
    reader,
    hub: HUB,
    instances: INSTANCES,
    registry: REGISTRY,
    pollMs: 0,
  };
  return { world, sent, deps };
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
