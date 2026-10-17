import { readFileSync } from "node:fs";
import { type Features, join } from "@grimworld/sim";
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
  trapSkills,
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
/** A seed skill row as `Registry.record` answers it: the header (to its target; no seed skill is elite) and entry 1, entries 2 and 3. */
function packedSkill(row: number[]): bigint[] {
  const header = [1, 2, 3, 4, 5, 6, 7, 8, 9].reduce(
    (bits, c, k) => bits + (BigInt(row[c]!) << [0n, 8n, 16n, 24n, 32n, 40n, 56n, 72n, 80n][k]!),
    0n,
  );
  const [e1, e2, e3] = [11, 23, 35].map((c) => entryBits(row.slice(c, c + 12)));
  return [join(header, e1!), join(e2!, e3!)];
}
function registry(count: { calls: [number, number][] } = { calls: [] }): RecordRead {
  return (kind, id) => {
    count.calls.push([kind, id]);
    const parts = recorded.get(`${kind}:${id}`);
    return Promise.resolve(parts === undefined ? [0n, 0n] : parts.map(BigInt));
  };
}

/** The skills `castes` name in their recorded sheets, then `effects`, once each and never 0. */
function lackingSkills(castes: number[], effects: number[]): number[] {
  const all = [...castes.flatMap((id) => readCasteSheet(id, partsOf(CASTE, id)).skills), ...effects];
  return [...new Set(all.filter((id) => id !== 0))];
}
/** The sheets of the skills among `ids` that the recording holds (the registry's others read as 0). */
const heldSheets = (ids: number[]) =>
  ids.filter((id) => recorded.has(`${SKILL}:${id}`)).map((id) => readSkillSheet(id, partsOf(SKILL, id)));

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

  it("reads the seed skills as their rows say", () => {
    // A skill the recording holds (skill 1) is read from it; the others, which the deployment
    // seeds since SEED-02, from the row packed as `seed_records` packs it (skill 1's pack is
    // checked against its recording below)
    for (const [id, row] of rows("skills", 47)) {
      const parts = recorded.has(`${SKILL}:${id}`) ? partsOf(SKILL, id) : packedSkill(row);
      // The first `REGENERATION` entry's `v0` and `v12`; none for the others
      const at = [11, 23, 35].find((c) => row[c] === 5);
      expect(readSkillSheet(id, parts)).toEqual({
        id,
        profession: row[1],
        kind: row[3],
        energy: row[4],
        adrenaline: row[5],
        activation: row[6],
        recharge: row[7],
        range: row[8],
        regen0: at === undefined ? 0 : row[at + 2],
        regen12: at === undefined ? 0 : row[at + 3],
        entry1: entryBits(row.slice(11, 23)),
        entry2: entryBits(row.slice(23, 35)),
        entry3: entryBits(row.slice(35, 47)),
      });
    }
  });

  it("packs a seed row as the recording of skill 1 holds it", () => {
    expect(packedSkill(rows("skills", 47).get(1)!)).toEqual(partsOf(SKILL, 1));
  });

  it("reads the deployment's Regeneration Potion (item 23): a regeneration of 3", () => {
    // No seed skill has a `REGENERATION` entry since CNT-01; devnet_deploy.py's `regeneration_item`:
    // `REGENERATION` (5), 3 at both ranks, 40 ticks at both, `SELF`, the ALLIES filter
    const entry = 5n + (3n << 16n) + (3n << 32n) + (40n << 48n) + (40n << 64n) + (1n << 88n) + (1n << 91n);
    expect(readPotionSheet(23, partsOf(ITEM, 23))).toEqual({
      id: 23,
      regen: 3,
      entry,
      range: 0,
      strength: 0,
    });
  });

  it("reads the deployment's potion: a heal of 20, not a regeneration", () => {
    // devnet_deploy.py's `item(POTION)`: `HEAL` (3), 20 at both ranks, `SELF`
    // and, since SEED-02 (#478), the ALLIES filter (bit 91): the word the recording holds
    const entry = 3n + (20n << 16n) + (20n << 32n) + (1n << 88n) + (1n << 91n);
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
  // These cases have no terrain trap in their ground: `[]`.
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
      [],
    );
    expect(content.castes.map((c) => c.id)).toEqual([2, 3, 1]);
    expect(content.castes[0]).toEqual(readCasteSheet(2, partsOf(CASTE, 2)));
    // The castes' skills as their recorded sheets name them, once each, then the effect's skill 1
    const lacking = lackingSkills([2, 3, 1], [1]);
    expect(content.skills).toEqual(heldSheets(lacking));
    expect(content.potions).toEqual([]);
    // Three castes, then each skill once (the castes' and the effect's)
    expect(count.calls).toEqual([
      [CASTE, 2],
      [CASTE, 3],
      [CASTE, 1],
      ...lacking.map((id) => [SKILL, id]),
    ]);
    expect(calls).toBe(3 + lacking.length);
  });

  it("does not read again a skill the members' content holds", async () => {
    const base = view();
    const { content, calls } = await assembleContent(
      { ...base, members: [member([1], [1], [])], goblins: [goblin(8, true, 1)] },
      registry(),
      [],
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
      [],
    );
    expect(content).toEqual({ skills: [], potions: [], castes: [] });
    expect(calls).toBe(3);
  });

  it("reads the recorded goblins' castes and their skills: the adventurer has an empty build, no belt", async () => {
    const recordedView = view();
    expect(recordedView.goblins.length).toBeGreaterThan(0);
    // The distinct castes (state bits 64-79), in the order the goblins are listed
    const castes = [
      ...new Set(recordedView.goblins.map((g) => Number((g.state >> 64n) & 0xffffn))),
    ];
    const count = { calls: [] as [number, number][] };
    const { content, calls } = await assembleContent(recordedView, registry(count), []);
    // Every listed goblin is derived: no held effect, the skills are the castes' only
    const lacking = lackingSkills(castes, []);
    expect(content).toEqual({
      skills: heldSheets(lacking),
      potions: [],
      castes: castes.map((caste) => readCasteSheet(caste, partsOf(CASTE, caste))),
    });
    expect(count.calls).toEqual([
      ...castes.map((caste) => [CASTE, caste]),
      ...lacking.map((id) => [SKILL, id]),
    ]);
    expect(calls).toBe(castes.length + lacking.length);
  });
});

/** The ground of a round: one chunk's three objects, each `[kind, state, param]`. */
function ground(...chunks: [number, number, number][][]): Features[] {
  const none = { tile: 0, kind: 0, state: 0, param: 0 };
  const pack = { tile: 0, template: 0, level: 0, count: 0, offsets: 0, alert: 0 };
  return chunks.map((objects) => ({
    packs: [pack, pack],
    objects: [0, 1, 2].map((i) => {
      const o = objects[i];
      return o === undefined ? none : { tile: i, kind: o[0], state: o[1], param: o[2] };
    }),
    touched: 0,
  }));
}
const TRAP = 4;
/** A registry that holds every skill (a header of profession 1), recording what it is asked. */
function holding(count: { calls: [number, number][] }): RecordRead {
  return (kind, id) => {
    count.calls.push([kind, id]);
    return Promise.resolve([LIVE + 1n, LIVE]);
  };
}
const bare = (): InstanceView => ({ ...view(), members: [member([], [], [])], goblins: [] });

describe("the terrain traps' skills (FIX-02b, GoblinsLibrary)", () => {
  it("reads each unused trap's skill once, in the chunks' order, and puts it in the content", async () => {
    const count = { calls: [] as [number, number][] };
    const traps = ground(
      [
        [TRAP, 0, 2],
        [TRAP, 0, 1],
      ],
      [[TRAP, 0, 2]],
    );
    expect(trapSkills(traps)).toEqual([2, 1]);
    const { content, calls } = await assembleContent(bare(), holding(count), traps);
    expect(count.calls).toEqual([
      [SKILL, 2],
      [SKILL, 1],
    ]);
    expect(calls).toBe(2);
    expect(content.skills.map((s) => s.id)).toEqual([2, 1]);
  });

  it("does not read a skill the members' content holds again", async () => {
    const count = { calls: [] as [number, number][] };
    const base = { ...bare(), members: [member([1], [], [])] };
    const { content } = await assembleContent(base, registry(count), ground([[TRAP, 0, 1]]));
    expect(count.calls).toEqual([[SKILL, 1]]);
    expect(content.skills.map((s) => s.id)).toEqual([1]);
  });

  it("reads nothing for a trap of param 0, a used one, or another kind of object", async () => {
    const count = { calls: [] as [number, number][] };
    const none = ground([
      [TRAP, 0, 0],
      [TRAP, 1, 1],
      [9, 0, 1],
    ]);
    expect(trapSkills(none)).toEqual([]);
    const { content, calls } = await assembleContent(bare(), registry(count), none);
    expect(count.calls).toEqual([]);
    expect(calls).toBe(0);
    expect(content.skills).toEqual([]);
  });

  it("reads 35 skills one record each (calls counts records, not MAX_READ bundles)", async () => {
    const count = { calls: [] as [number, number][] };
    const ids = Array.from({ length: 35 }, (_, k) => 100 + k);
    const chunks = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((k) =>
      ids.slice(3 * k, 3 * k + 3).map((id): [number, number, number] => [TRAP, 0, id]),
    );
    const traps = ground(...chunks);
    expect(trapSkills(traps)).toEqual(ids);
    const { content, calls } = await assembleContent(bare(), holding(count), traps);
    expect(count.calls).toEqual(ids.map((id) => [SKILL, id]));
    expect(calls).toBe(35);
    expect(content.skills.map((s) => s.id)).toEqual(ids);
  });

  it("raises NotMirrored naming a trap skill the registry lacks", async () => {
    await expect(
      assembleContent(
        bare(),
        registry(),
        ground([
          [TRAP, 0, 1],
          [TRAP, 0, 77],
        ]),
      ),
    ).rejects.toThrow(/terrain trap skill 77 not in the registry/);
  });
});
