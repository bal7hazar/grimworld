import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  CASTE,
  ITEM,
  type RecordRead,
  SKILL,
  assembleContent,
  memberContent,
  readCasteSheet,
  readPotionSheet,
  readSkillSheet,
} from "./content";
import { recordedBefore, recordedRecords } from "./recorded-goblins";
import { type GoblinView, type InstanceView, type MemberView, decodeInstanceView } from "./view";

const LIVE = 1n << 250n;
const P128 = 1n << 128n;

/** The seed the deployment writes (contracts/seed/test-region.json), its rows by id. */
const seed = JSON.parse(
  readFileSync(new URL("../../../../contracts/seed/test-region.json", import.meta.url), "utf8"),
) as Record<string, number[]>;
function rows(name: string, columns: number): Map<number, number[]> {
  const flat = seed[name]!;
  const out = new Map<number, number[]>();
  for (let at = 0; at < flat.length; at += columns)
    out.set(flat[at]!, flat.slice(at, at + columns));
  return out;
}

/** `EntryTrait::pack` of a seed row's 12 entry columns (`seed_records.entry_bits`). */
function entryBits(row: number[]): bigint {
  const shifts = [0n, 8n, 16n, 32n, 48n, 64n, 80n, 86n, 88n, 91n, 92n, 95n];
  return row.reduce((bits, v, k) => bits + (BigInt(v) << shifts[k]!), 0n);
}

/** The recorded records, as `Registry.record` answers them; zeros for any other. */
const recorded = new Map(recordedRecords.map(([kind, id, parts]) => [`${kind}:${id}`, parts]));
const partsOf = (kind: number, id: number): bigint[] => recorded.get(`${kind}:${id}`)!.map(BigInt);
function registry(count: { calls: [number, number][] } = { calls: [] }): RecordRead {
  return (kind, id) => {
    count.calls.push([kind, id]);
    const parts = recorded.get(`${kind}:${id}`);
    return Promise.resolve(parts === undefined ? [0n, 0n] : parts.map(BigInt));
  };
}

const view = (): InstanceView => decodeInstanceView(recordedBefore.view.map(BigInt));
/** A goblin of caste `caste` (state bits 64–79), its held effect's skill at timers bits 108–123. */
const goblin = (entity: number, derived: boolean, caste: number, effect = 0): GoblinView => ({
  entity,
  derived,
  state: LIVE + (BigInt(caste) << 64n),
  timers: LIVE + (BigInt(effect) << 108n),
});
/** A member of `bar` skills, `kit` items, and effects of `[carrier, potion]`. */
function member(bar: number[], kit: number[], effects: [number, boolean][]): MemberView {
  const base = view().members[0]!;
  const lanes = (values: number[], width: bigint) =>
    values.reduce((word, v, k) => word + (BigInt(v) << (width * BigInt(k))), 0n);
  const held = effects.map(([carrier, potion]) => BigInt(carrier) + (potion ? 1n << 23n : 0n));
  const effectsWord =
    (held[0] ?? 0n) +
    ((held[1] ?? 0n) << 56n) +
    ((held[2] ?? 0n) + ((held[3] ?? 0n) << 56n)) * P128;
  return {
    ...base,
    bar: LIVE + lanes(bar, 16n),
    kit: LIVE + lanes(kit, 32n),
    effects: LIVE + effectsWord,
  };
}

describe("the sheets read from the recorded records", () => {
  it("reads every seed caste as its row says", () => {
    for (const [id, row] of rows("castes", 30)) {
      const vs = row.slice(6, 15).reduce((bits, v, k) => bits + (BigInt(v) << BigInt(6 * k)), 0n);
      expect(readCasteSheet(id, partsOf(CASTE, id))).toEqual({
        id,
        health: row[3],
        health_regen: row[4],
        armor: row[5],
        armor_vs: vs,
        weapon: row[15],
        weapon_damage: row[16],
        damage_type: row[17],
        weapon_ticks: row[18],
        weapon_range: row[19],
        energy: row[20],
        energy_regen: row[21],
        skills: row.slice(22, 26),
        rank: row[26],
      });
    }
  });

  it("reads the seed skill as its row says", () => {
    for (const [id, row] of rows("skills", 47)) {
      expect(readSkillSheet(id, partsOf(SKILL, id))).toEqual({
        id,
        profession: row[1],
        kind: row[3],
        energy: row[4],
        adrenaline: row[5],
        activation: row[6],
        recharge: row[7],
        range: row[8],
        // No `REGENERATION` entry
        regen0: 0,
        regen12: 0,
        entry1: entryBits(row.slice(11, 23)),
        entry2: entryBits(row.slice(23, 35)),
        entry3: entryBits(row.slice(35, 47)),
      });
    }
  });

  it("reads the deployment's potion: a heal of 20, not a regeneration", () => {
    // devnet_deploy.py's `item(POTION)`: `HEAL` (3), 20 at both ranks, `SELF`
    const entry = 3n + (20n << 16n) + (20n << 32n) + (1n << 88n);
    expect(readPotionSheet(1, partsOf(ITEM, 1))).toEqual({
      id: 1,
      regen: 0,
      entry,
      range: 0,
      strength: 0,
    });
  });

  it("finds a REGENERATION entry's line, signed, and stops at an empty entry", () => {
    const regen = 5n + (0xfffdn << 16n) + (7n << 32n);
    const header = 2n + (4n << 16n) + (3n << 24n);
    // Entry 1 a heal, entry 2 the regeneration (v0 −3, v12 7)
    const parts = [header + (3n << 128n) + LIVE, regen + LIVE];
    expect(readSkillSheet(4, parts)).toMatchObject({ regen0: -3, regen12: 7, kind: 4, energy: 3 });
    // Entry 1 empty: the search stops before the regeneration
    expect(readSkillSheet(4, [header + LIVE, regen + LIVE])).toMatchObject({
      regen0: 0,
      regen12: 0,
    });
    // A potion's regeneration (v0 −2), its range 3 and strength 9 above its 97 bits
    const potion = (5n + (0xfffen << 16n) + (3n << 97n) + (9n << 105n)) * P128 + LIVE;
    expect(readPotionSheet(2, [potion])).toMatchObject({ regen: -2, range: 3, strength: 9 });
  });
});

describe("the content assembled as PlayLibrary assembles it", () => {
  it("takes each member's bar, then each slot's belt item and held skill, 0 and repeats skipped", () => {
    const one = member(
      [0, 5, 3, 5],
      [8, 0, 8, 1],
      [
        [7, false],
        [2, true],
        [3, false],
        [9, false],
      ],
    );
    const two = member([6], [0, 0, 0, 4], []);
    expect(memberContent([one, two])).toEqual({ skills: [5, 3, 7, 9, 6], potions: [8, 1, 4] });
  });

  it("reads the members' sheets and the goblins' castes, derived first, then the skills it lacks", async () => {
    const base = view();
    const count = { calls: [] as [number, number][] };
    const { content, calls } = await assembleContent(
      {
        ...base,
        members: [member([], [], [])],
        // Stored goblin 30 holds skill 1's effect; derived 8 and 9 share caste 2
        goblins: [
          goblin(8, true, 2),
          goblin(9, true, 2),
          goblin(24, false, 3),
          goblin(30, false, 1, 1),
        ],
      },
      registry(count),
    );
    expect(content.castes.map((c) => c.id)).toEqual([2, 3, 1]);
    expect(content.castes[0]).toEqual(readCasteSheet(2, partsOf(CASTE, 2)));
    expect(content.skills).toEqual([readSkillSheet(1, partsOf(SKILL, 1))]);
    expect(content.potions).toEqual([]);
    // Three castes, then skill 1 once (the castes' and the effect's)
    expect(count.calls).toEqual([
      [CASTE, 2],
      [CASTE, 3],
      [CASTE, 1],
      [SKILL, 1],
    ]);
    expect(calls).toBe(4);
  });

  it("does not read again a skill the members' content holds", async () => {
    const base = view();
    const { content, calls } = await assembleContent(
      { ...base, members: [member([1], [1], [])], goblins: [goblin(8, true, 1)] },
      registry(),
    );
    expect(content.skills.map((s) => s.id)).toEqual([1]);
    expect(content.potions.map((p) => p.id)).toEqual([1]);
    expect(content.castes.map((c) => c.id)).toEqual([1]);
    expect(calls).toBe(3);
  });

  it("skips a record the registry lacks, as `exists` does", async () => {
    const base = view();
    const { content, calls } = await assembleContent(
      { ...base, members: [member([40], [41], [])], goblins: [goblin(8, true, 42)] },
      registry(),
    );
    expect(content).toEqual({ skills: [], potions: [], castes: [] });
    expect(calls).toBe(3);
  });

  it("reads the recorded goblin's caste and its skill: the adventurer has an empty build, no belt", async () => {
    const recordedView = view();
    expect(recordedView.goblins).toHaveLength(1);
    const [listed] = recordedView.goblins;
    const caste = Number((listed!.state >> 64n) & 0xffffn);
    const count = { calls: [] as [number, number][] };
    const { content, calls } = await assembleContent(recordedView, registry(count));
    expect(content).toEqual({
      skills: [readSkillSheet(1, partsOf(SKILL, 1))],
      potions: [],
      castes: [readCasteSheet(caste, partsOf(CASTE, caste))],
    });
    expect(count.calls).toEqual([
      [CASTE, caste],
      [SKILL, 1],
    ]);
    expect(calls).toBe(2);
  });
});
