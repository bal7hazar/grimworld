import { readFileSync } from "node:fs";
import { Felts, type PotionSheet, type SkillSheet, join, readContent } from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import { readPotionSheet, readSkillSheet } from "./content";

// The readers on RV-03c's content (contracts/logic/vectors/tick.jsonl, row 0, `fn` `content`): the
// table's `Content` is decoded sheets (`SkillSheet`, `PotionSheet`), while the readers decode the
// Registry's records, so the records are rebuilt from the row's sheets and the readers' sheets are
// compared with the row's (the level they share). The record is packed as `SkillSheetTrait::read`
// and `PotionSheetTrait::read` unpack it: a skill's header limb (profession 0–7, attribute 8–15,
// kind, energy, adrenaline, activation 16 bits, recharge 16 bits, range) and its entry 1 on the
// first record's high limb, entries 2 and 3 on the second's two limbs; a potion's entry (97 bits),
// range and strength on its high limb. The entries (where `REGENERATION`'s pips are) are the row's
// bits as they are. The attribute is not in a sheet: 0.
const row = JSON.parse(
  readFileSync(
    new URL("../../../../contracts/logic/vectors/tick.jsonl", import.meta.url),
    "utf8",
  ).split("\n")[0]!,
) as { id: number; fn: string; ok: string[] };
const content = readContent(new Felts(row.ok.map((felt) => BigInt(felt))));

/** `Registry.record(SKILL, id)`'s two parts for a sheet. */
function skillParts(sheet: SkillSheet): bigint[] {
  const shifts = [0n, 16n, 24n, 32n, 40n, 56n, 72n];
  const header = [
    sheet.profession,
    sheet.kind,
    sheet.energy,
    sheet.adrenaline,
    sheet.activation,
    sheet.recharge,
    sheet.range,
  ].reduce((bits, value, k) => bits + (BigInt(value) << shifts[k]!), 0n);
  return [join(header, sheet.entry1), join(sheet.entry2, sheet.entry3)];
}

/** `Registry.record(ITEM, id)`'s part for a potion's sheet. */
const potionParts = (sheet: PotionSheet): bigint[] => [
  join(0n, sheet.entry + (BigInt(sheet.range) << 97n) + (BigInt(sheet.strength) << 105n)),
];

describe("the readers on tick.jsonl row 0", () => {
  it("is the content row", () => {
    expect(row).toMatchObject({ id: 0, fn: "content" });
  });

  it("readSkillSheet decodes skill 80's REGENERATION: 2 at rank 0, 6 at rank 12", () => {
    const sheet = content.skills.find((skill) => skill.id === 80)!;
    expect(sheet.entry1 % 256n).toBe(5n); // kind::REGENERATION
    expect(readSkillSheet(80, skillParts(sheet))).toEqual(sheet);
    expect(readSkillSheet(80, skillParts(sheet))).toMatchObject({ regen0: 2, regen12: 6 });
  });

  it("readSkillSheet reads every skill of the row as the row has it", () => {
    for (const sheet of content.skills)
      expect(readSkillSheet(sheet.id, skillParts(sheet))).toEqual(sheet);
  });

  it("readPotionSheet decodes potion 101's REGENERATION 3", () => {
    const sheet = content.potions.find((potion) => potion.id === 101)!;
    expect(sheet.entry % 256n).toBe(5n); // kind::REGENERATION
    expect(readPotionSheet(101, potionParts(sheet))).toEqual(sheet);
    expect(readPotionSheet(101, potionParts(sheet))).toMatchObject({ regen: 3 });
  });

  it("readPotionSheet reads every potion of the row as the row has it", () => {
    for (const sheet of content.potions)
      expect(readPotionSheet(sheet.id, potionParts(sheet))).toEqual(sheet);
  });
});
