import { readFileSync } from "node:fs";
import { Felts, type PotionSheet, type SkillSheet, join, readContent } from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import { readPotionSheet, readSkillSheet } from "./content";

// The readers on RV-03c's content (contracts/logic/vectors/tick.jsonl, row 0, `fn` `content`): the
// table's `Content` is decoded sheets (`SkillSheet`, `PotionSheet`), while the readers decode the
// Registry's records, so the records are rebuilt from the row's sheets and the readers' sheets are
// compared with the row's (the level they share). The layout is the writers': `SkillRecord::pack`
// (contracts/logic/src/models/skill.cairo) and `ItemRecord::pack` (models/item.cairo), not the
// readers'. A skill's header limb is profession 0–7, attribute 8–15, kind 16–23, energy 24–31,
// adrenaline 32–39, activation 40–55, recharge 56–71, range 72–79, target 80–81 and elite 82, and
// its entry 1 on the first record's high limb; entries 2 and 3 are the second record's two limbs.
// A potion (an Item) is one record: class 0–7, region 8–23, rarity 24–31, value 32–63 and book
// index 64–… on its low limb, its entry (97 bits), range and strength on its high limb. The
// entries (where `REGENERATION`'s pips are) are the row's bits as they are. A sheet holds neither
// the skill's attribute, target and elite nor the item's low limb, which the readers skip: the
// repack sets them to non-zero values, so a reader that took any of them would show.
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
  // attribute (bits 8–15), target (80–81) and elite (82): not in a sheet, the readers skip them
  const skipped = (0xa5n << 8n) + (3n << 80n) + (1n << 82n);
  const header = skipped + [
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
  // The low limb (class 0–7, region, rarity, value, book index) is the reader's to skip
  join(0xa5n, sheet.entry + (BigInt(sheet.range) << 97n) + (BigInt(sheet.strength) << 105n)),
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
