// The goblin's load and what it refuses (CLI-02g-B1), the words it reads and writes, and the
// world's awake check. The refusals are `parity/refusals.ts`'s cases, which the mutation check
// runs too. The cases marked "hand copy" are `models/goblin.cairo`'s and `types/world.cairo`'s own
// unit tests, copied by hand: Cairo's fixtures do not reach this file by themselves, and no table
// records them.

import { describe, expect, it } from "vitest";
import { CairoPanic } from "../felt";
import { LIVE } from "../packing";
import { REFUSALS, HOB, RUNT, caste, content, goblin, refused, skill } from "../parity/refusals";
import { type Sheets, sheets as index } from "./words";
import {
  adrenaline_cap,
  assert_pips,
  at,
  crippled,
  effect_of,
  energy_regen,
  health_regen,
  hot,
  is_alive,
  level,
  load,
  max_energy,
  place,
  recharge,
  set_crippled,
  set_effect,
  set_place,
  set_recharge,
  store,
} from "./goblin";
import { world } from "./world";

const two = (bits: number): bigint => 1n << BigInt(bits);
const NONE = 255;
const SMASH = 24;
const sheets = (): Sheets => index(content());

describe("the goblin's refusals, fail closed", () => {
  for (const refusal of REFUSALS) {
    it(`refuses ${refusal.name} with "${refusal.panic}"`, () => {
      expect(() => refused(refusal)).not.toThrow();
      // And with Cairo's panic, not another error
      expect(refusal.run).toThrow(CairoPanic);
    });
  }

  it("loads eight awake goblins (test_defeat_in_step_1_with_eight_awake, hand copy: the boundary)", () => {
    const goblins = Array.from({ length: 8 }, (_, k) => goblin(8 + k, HOB));
    const loaded = world({ clock: 0, members: [], goblins, killed: [], defeated: false }, sheets());
    expect(loaded.goblins).toHaveLength(8);
  });

  it("counts the awake, not the goblins: nine goblins, one asleep", () => {
    const goblins = Array.from({ length: 9 }, (_, k) => goblin(8 + k, HOB));
    goblins[0] = { ...goblins[0]!, awake: false };
    const loaded = world({ clock: 0, members: [], goblins, killed: [], defeated: false }, sheets());
    expect(loaded.goblins.filter((g) => g.awake)).toHaveLength(8);
  });

  it("accepts the pips an i8 holds", () => {
    // −128 and 127 are the bounds (the kind's own are ±10)
    for (const pips of [-128, -10, 0, 10, 127]) expect(() => assert_pips(pips)).not.toThrow();
  });
});

describe("GoblinTrait::load", () => {
  // models/goblin.cairo `test_goblin_load`: hand copy. Level 20, caste 3; its effect is skill 24
  // at rank 8: 1 + 3 × 8 / 12 = 3.
  it("derives the maxima, the regeneration, the effect's pips and the kit's cap (test_goblin_load)", () => {
    const smash = skill(SMASH, { kind: 1, adrenaline: 5, regen0: 1, regen12: 4 });
    const own = caste(3, 2, {
      health: 150,
      health_regen: 12,
      energy: 20,
      energy_regen: 2,
      skills: [SMASH, 0, 0, 0],
    });
    const from = {
      skills: [skill(1), smash],
      potions: [],
      castes: [caste(HOB, 1), own],
    };
    // caste id 3 sits second in the list
    const words = {
      entity: 77,
      awake: false,
      state: LIVE + 3n * two(64) + 20n * two(80),
      timers: LIVE + 255n + BigInt(SMASH) * two(108) + 8n * two(246),
    };
    const sheet = index(from);
    const loaded = load(words, sheet);
    expect(loaded.max_health).toBe(720);
    expect(health_regen(loaded, sheet)).toBe(2);
    expect(max_energy(loaded, sheet)).toBe(60);
    expect(energy_regen(loaded, sheet)).toBe(2);
    expect(loaded.effect_regen).toBe(3);
    expect(loaded.awake).toBe(false);
    expect(loaded.caste_at).toBe(1);
    expect(adrenaline_cap(loaded, sheet)).toBe(20);
  });

  // models/goblin.cairo `test_goblin_hot`: hand copy.
  it("reads the hot fields of the words (test_goblin_hot)", () => {
    const words = goblin(8, RUNT);
    const fields = hot(words.state, words.timers);
    expect([fields.ai, fields.health, fields.caste]).toEqual([3, 100, RUNT]);
    expect([fields.act_slot, fields.level]).toEqual([NONE, 10]);
  });

  // models/goblin.cairo `test_goblin_load_store`: hand copy. Caste 2, level 10.
  it("loads Fixture::goblin as the fixture and stores a round trip (test_goblin_load_store)", () => {
    const sheet = sheets();
    const words = goblin(9, RUNT);
    const loaded = load(words, sheet);
    expect(loaded).toEqual({
      entity: 9,
      awake: true,
      ai: 3,
      health: 100,
      energy: 0,
      adrenaline: 0,
      caste: RUNT,
      act_slot: NONE,
      act_target: 0,
      act_deadline: 0,
      bleeding: 0,
      poison: 0,
      burning: 0,
      knocked: 0,
      effect_deadline: 0,
      effect_regen: 0,
      max_health: 280,
      caste_at: 1,
      effect_at: 0xffffffff,
      state: words.state,
      timers: words.timers,
    });
    expect(store(loaded)).toEqual(words);
    const changed = { ...loaded };
    changed.health = 3;
    changed.poison = 88;
    changed.effect_deadline = 90;
    // `start(2, 8, 2, 70)`: slot 2, target 8, deadline 70 + 2
    [changed.act_slot, changed.act_target, changed.act_deadline] = [2, 8, 72];
    set_recharge(changed, 3, 500);
    const back = load(store(changed), sheet);
    expect(back.state).toBe(store(changed).state);
    expect([back.health, back.poison, back.effect_deadline]).toEqual([3, 88, 90]);
    expect([back.act_slot, back.act_target, back.act_deadline]).toEqual([2, 8, 72]);
    expect(recharge(back, 3)).toBe(500);
  });

  it("writes each hot field in its own place and no other bit", () => {
    const sheet = sheets();
    const base = load(goblin(9, HOB), sheet);
    const fields = {
      ai: [two(24), 5],
      health: [two(32), 777],
      energy: [two(48), 9],
      adrenaline: [two(56), 200],
    } as const;
    for (const [key, [shift, value]] of Object.entries(fields)) {
      const changed = { ...base, [key]: value };
      const words = store(changed);
      expect(words.timers).toBe(base.timers);
      const old = base[key as keyof typeof fields] as number;
      expect(words.state - base.state).toBe(BigInt(value - old) * shift);
    }
    const timers = {
      act_slot: [1n, 3],
      act_target: [two(8), 500],
      act_deadline: [two(24), 99],
      bleeding: [two(52), 40],
      poison: [two(80), 41],
      burning: [two(128), 42],
      knocked: [two(184), 43],
      effect_deadline: [two(212), 44],
    } as const;
    for (const [key, [shift, value]] of Object.entries(timers)) {
      const changed = { ...base, [key]: value };
      const words = store(changed);
      expect(words.state).toBe(base.state);
      const old = base[key as keyof typeof timers] as number;
      expect(words.timers - base.timers).toBe(BigInt(value - old) * shift);
    }
  });

  it("is alive below DEAD", () => {
    expect([0, 3, 5, 6, 7].map((ai) => is_alive({ ai }))).toEqual([true, true, true, false, false]);
  });

  it("refuses a caste regeneration above an i8 and an energy above a u8 product", () => {
    const sheet = index({
      ...content(),
      castes: [caste(HOB, 1, { health_regen: 255, energy: 100 }), caste(RUNT, 2)],
    });
    const loaded = load(goblin(9, HOB), sheet);
    expect(() => health_regen(loaded, sheet)).toThrow(CairoPanic);
    expect(() => max_energy(loaded, sheet)).toThrow(CairoPanic);
  });
});

describe("the fields of the words", () => {
  const base = () => load(goblin(9, HOB), sheets());

  it("reads and sets the recharge of each caste skill, 28 bits apart", () => {
    const g = base();
    for (const [slot, deadline] of [
      [0, 11],
      [1, 22],
      [2, 33],
      [3, 44],
    ] as const) {
      set_recharge(g, slot, deadline);
    }
    expect([0, 1, 2, 3].map((slot) => recharge(g, slot))).toEqual([11, 22, 33, 44]);
    set_recharge(g, 1, 5);
    expect([0, 1, 2, 3].map((slot) => recharge(g, slot))).toEqual([11, 5, 33, 44]);
    expect(() => recharge(g, 4)).toThrow(CairoPanic);
    expect(() => set_recharge(g, 4, 1)).toThrow(CairoPanic);
  });

  it("reads and sets Crippled's deadline (timers 156–183)", () => {
    const g = base();
    const before = g.timers;
    set_crippled(g, 70);
    expect(crippled(g)).toBe(70);
    expect(g.timers - before).toBe(70n * two(156));
    set_crippled(g, 3);
    expect(crippled(g)).toBe(3);
  });

  it("reads and sets the one effect with its carrier, charges, rank, deadline and pips", () => {
    const g = base();
    expect(effect_of(g)).toEqual({ carrier: 0, potion: false, charges: 0, deadline: 0, rank: 0 });
    set_effect(g, { carrier: 15, potion: false, charges: 5, deadline: 44, rank: 12 }, -7);
    expect(effect_of(g)).toEqual({
      carrier: 15,
      potion: false,
      charges: 5,
      deadline: 44,
      rank: 12,
    });
    expect(g.effect_deadline).toBe(44);
    expect(g.effect_regen).toBe(-7);
    // The words say the same through `hot`, and nothing else moved
    const fields = hot(g.state, g.timers);
    expect([fields.effect, fields.rank, fields.act_slot]).toEqual([15, 12, NONE]);
    set_effect(g, { carrier: 0, potion: false, charges: 0, deadline: 0, rank: 0 }, 0);
    expect(g.timers).toBe(LIVE + BigInt(NONE));
    expect(() =>
      set_effect(g, { carrier: 1, potion: false, charges: 0, deadline: 0, rank: 0 }, 128),
    ).toThrow(RangeError);
  });

  it("reads and sets its place, and reads its level", () => {
    const g = base();
    expect(place(g)).toEqual({ x: 0, y: 0, facing: 0 });
    set_place(g, 21, 33, 4);
    expect(place(g)).toEqual({ x: 21, y: 33, facing: 4 });
    expect(at(g.state)).toEqual({ x: 21, y: 33, facing: 4 });
    expect(level(g)).toBe(10);
    // The hot fields are where they were
    expect(hot(g.state, g.timers)).toMatchObject({ ai: 3, health: 100, level: 10 });
    set_place(g, 0, 0, 0);
    expect(g.state).toBe(goblin(9, HOB).state);
  });
});
