// TEST SCAFFOLDING (CLI-02g-B1): the refusals `GoblinTrait::load` and `WordsTrait::indexed` make,
// as cases the unit tests run (`segment/goblin.test.ts`) and the mutation check runs against its
// copies of `src/` (`mutants.test.ts`), so that one list of cases decides both. No row of
// `segment2.jsonl` records a refusal, so the tables cannot kill a mutant that drops one; these
// cases do. Never exported by `src/index.ts`.
//
// The fixtures are **hand copies** of `models/goblin.cairo`'s and `types/world/fixtures.cairo`'s:
// `Fixture::content` (castes 1 and 2, skills `20 + 4 caste + slot`), `Fixture::goblin` (an awake,
// Engaged goblin at level 10, health 100) and `Fixture::skill`/`caste`. They are not generated from
// Cairo: a change to those fixtures does not reach here by itself.

import { CairoPanic } from "../felt";
import { LIVE } from "../packing";
import { assert_pips, load as loadGoblin } from "../segment/goblin";
import { assert_awake, world } from "../segment/world";
import { sheets } from "../segment/words";
import type { CasteSheet, Content, GoblinWords, SkillSheet } from "../segment/words";

const two = (bits: number): bigint => 1n << BigInt(bits);

export const HOB = 1;
export const RUNT = 2;
/** `ai::ENGAGED` and `activation::NONE`. */
const ENGAGED = 3;
const NONE = 255;

/** `Fixture::skill`: a skill of `id`, every other field 0. */
export function skill(id: number, extra: Partial<SkillSheet> = {}): SkillSheet {
  return {
    id,
    kind: 0,
    energy: 0,
    profession: 0,
    adrenaline: 0,
    activation: 0,
    recharge: 0,
    regen0: 0,
    regen12: 0,
    range: 0,
    entry1: 0n,
    entry2: 0n,
    entry3: 0n,
    ...extra,
  };
}

/** `Fixture::caste`: multiplier 100 %, no regeneration, 10 energy regenerating 1, skills `20 + 4 id + slot`. */
export function caste(id: number, k: number, extra: Partial<CasteSheet> = {}): CasteSheet {
  const first = 20 + 4 * id;
  return {
    id,
    health: 100,
    health_regen: 10,
    energy: 10,
    energy_regen: 1,
    weapon_ticks: k,
    skills: [first, first + 1, first + 2, first + 3],
    armor: 0,
    armor_vs: 0n,
    weapon: 0,
    weapon_damage: 0,
    damage_type: 0,
    weapon_range: 0,
    rank: 0,
    ...extra,
  };
}

/** `Fixture::content`: the bar's skills 1–8, the castes' skills, castes `HOB` and `RUNT`. */
export function content(): Content {
  const skills = Array.from({ length: 8 }, (_, at) => skill(at + 1));
  for (const id of [HOB, RUNT]) {
    for (let slot = 0; slot < 4; slot++) skills.push(skill(20 + 4 * id + slot));
  }
  return { skills, potions: [], castes: [caste(HOB, 1), caste(RUNT, 2)] };
}

/** `Fixture::goblin`'s words: awake, Engaged, health 100, level 10, no activation, no effect. */
export function goblin(entity: number, id: number): GoblinWords {
  return {
    entity,
    awake: true,
    state: LIVE + BigInt(ENGAGED) * two(24) + 100n * two(32) + BigInt(id) * two(64) + 10n * two(80),
    timers: LIVE + BigInt(NONE),
  };
}

/** A refusal: the case, and the panic data Cairo gives it. */
export type Refusal = { name: string; panic: string; run: () => void };

/** Runs a refusal: fails unless it panics with exactly Cairo's data. */
export function refused(refusal: Refusal): void {
  try {
    refusal.run();
  } catch (error) {
    if (error instanceof CairoPanic && error.data.length === 1 && error.data[0] === refusal.panic) {
      return;
    }
    throw new Error(`${refusal.name}: expected "${refusal.panic}", got ${String(error)}`, {
      cause: error,
    });
  }
  throw new Error(`${refusal.name}: expected "${refusal.panic}", nothing was refused`);
}

const load = (words: GoblinWords, from: Content): void => {
  loadGoblin(words, sheets(from));
};

/** `nine_awake`'s goblins (`types/world.cairo`): entities 8 to 16, all awake. */
const nine = (): GoblinWords[] => Array.from({ length: 9 }, (_, at) => goblin(8 + at, HOB));

export const REFUSALS: readonly Refusal[] = [
  {
    // models/goblin.cairo `test_goblin_load_missing_skill`: hand copy. Caste 1's skills are 24 to
    // 27 and only 24 is in the content.
    name: "a caste skill missing from the content (test_goblin_load_missing_skill)",
    panic: "tick: skill not in content",
    run: () =>
      load(goblin(9, HOB), {
        skills: [skill(24, { kind: 1, activation: 3, recharge: 10 })],
        potions: [],
        castes: [caste(HOB, 1)],
      }),
  },
  {
    // No Cairo unit test: `IndexTrait::caste`'s `NO_CASTE`, the caste 3 of a content of two.
    name: "a caste missing from the content",
    panic: "tick: caste not in content",
    run: () => load(goblin(9, 3), content()),
  },
  {
    // No Cairo unit test: `index.skill(effect)` in `GoblinTrait::load`, an effect of skill 99.
    name: "an effect's skill missing from the content",
    panic: "tick: skill not in content",
    run: () => load({ ...goblin(9, HOB), timers: LIVE + BigInt(NONE) + 99n * two(108) }, content()),
  },
  {
    // models/goblin.cairo `test_goblin_assert_pips`: hand copy, −129.
    name: "regeneration pips below an i8 (test_goblin_assert_pips)",
    panic: "goblin: regeneration above i8",
    run: () => assert_pips(-129),
  },
  {
    name: "regeneration pips above an i8",
    panic: "goblin: regeneration above i8",
    run: () => assert_pips(128),
  },
  {
    // `GoblinTrait::load`'s `assert_pips` on the effect's pips: skill 5 at rank 12 gives
    // 0 + (1000 − 0) × 12 / 12 = 1000.
    name: "an effect's regeneration above an i8, through the load",
    panic: "goblin: regeneration above i8",
    run: () =>
      load(
        { ...goblin(9, HOB), timers: LIVE + BigInt(NONE) + 5n * two(108) + 12n * two(246) },
        {
          ...content(),
          skills: content().skills.map((s) => (s.id === 5 ? { ...s, regen12: 1000 } : s)),
        },
      ),
  },
  {
    // `CasteSheet::max_health`'s `try_into` to a `u16`: level 255 of a 65535 % caste is
    // 5180 × 65535 / 100 = 3,394,713, above 65535.
    name: "a max health above a u16",
    panic: "Option::unwrap failed.",
    run: () =>
      load(
        { ...goblin(9, HOB), state: goblin(9, HOB).state + 245n * two(80) },
        { ...content(), castes: [caste(HOB, 1, { health: 65535 }), caste(RUNT, 2)] },
      ),
  },
  {
    // types/world.cairo `test_world_assert_awake_loaded`: hand copy, without the member (the
    // check is the goblins' pass). `_perceived` and `test_world_assert_awake` run
    // `TickTrait::run`, not ported (Lot B), and are not copied.
    name: "nine goblins awake at a load (test_world_assert_awake_loaded)",
    panic: "tick: more than 8 awake",
    run: () =>
      world(
        { clock: 0, members: [], goblins: nine(), killed: [], defeated: false },
        sheets(content()),
      ),
  },
  {
    name: "nine indexes in the awake set (WorldAssert::assert_awake)",
    panic: "tick: more than 8 awake",
    run: () => assert_awake([0, 1, 2, 3, 4, 5, 6, 7, 8]),
  },
];
