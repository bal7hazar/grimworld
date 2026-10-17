#!/usr/bin/env node
// CNT-01's fight check (D-309, item 5): each MVP profession at level 1, with its kit (the six
// starter skills of `contracts/seed/test-region.json`'s `KIT` row and its starter weapon), against
// the gate pack (`PACK` 5, the Heart of the gate zone, `LOCATION` 5), fought on track CV's mirror of
// the tick (`client/sim`). Prints, per profession, whether it wins, the ticks it took and the health
// left, then a JSON line.
//
//   node scripts/gate2_sim.mjs [--goblins N]   (after `pnpm install --frozen-lockfile`, for
//                                              @scure/starknet; N: the pack's first N goblins only)
//
// The sim is TypeScript only: a module hook resolves its extensionless imports and strips its
// types (`node:module`'s `stripTypeScriptTypes`, as `client/sim/src/parity/mutate.ts` does), so no
// build step and nothing inside `client/` changes. The sim has no player: the autopilot below picks
// each action, a plain priority list per profession, and is the check's own assumption.
import { readFileSync, statSync } from "node:fs";
import { registerHooks, stripTypeScriptTypes } from "node:module";
import { fileURLToPath } from "node:url";

const ROOT = new URL("../", import.meta.url);
const SRC = new URL("client/sim/src/", ROOT).href;

const isFile = (url) => {
  try {
    return statSync(fileURLToPath(url)).isFile();
  } catch {
    return false;
  }
};

registerHooks({
  resolve(specifier, context, nextResolve) {
    const parent = context.parentURL;
    if (parent !== undefined && parent.startsWith(SRC) && specifier.startsWith(".")) {
      const url = new URL(specifier, parent).href;
      for (const candidate of [`${url}.ts`, `${url}/index.ts`, url]) {
        if (isFile(candidate)) return { url: candidate, format: "module", shortCircuit: true };
      }
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (!url.startsWith(SRC) || !url.endsWith(".ts")) return nextLoad(url, context);
    const text = readFileSync(fileURLToPath(url), "utf8");
    const source = stripTypeScriptTypes(text, { mode: "transform", sourceUrl: url });
    return { format: "module", source, shortCircuit: true };
  },
});

const sim = await import(new URL("index.ts", SRC).href);
const { LIVE, actionAct, distance, facing, goblinPlace, indexSheets, loadWorld, memberPlace } = sim;
const { runSegment, tickTicks, trapTrigger } = sim;
const { board, position } = await import(new URL("movement.ts", SRC).href);
const CLASSES = { act: actionAct, ticks: tickTicks, trigger: trapTrigger };

// ---- the seed

const SEED = JSON.parse(readFileSync(new URL("contracts/seed/test-region.json", ROOT), "utf8"));
const rows = (name, columns) => {
  const flat = SEED[name];
  const out = [];
  for (let i = 0; i < flat.length; i += columns) out.push(flat.slice(i, i + columns));
  return out;
};
const byId = (table) => new Map(table.map((row) => [row[0], row]));
const SKILLS = byId(rows("skills", 47));
const CASTES = byId(rows("castes", 30));
const PACKS = byId(rows("packs", 17));
const KITS = byId(rows("kits", 8));
const QUOTAS = rows("quotas", 19);
const LOCATIONS = byId(rows("locations", 31));

const b = BigInt;
/** `EntryTrait::pack` (the seed's values are not negative). */
function entryBits(e) {
  const [kind, param, v0, v12, d0, d12, charges, target, shape, filter, guard, scope] = e.map(b);
  return (kind + (param << 8n) + (v0 << 16n) + (v12 << 32n) + (d0 << 48n) + (d12 << 64n)
    + (charges << 80n) + (target << 86n) + (shape << 88n) + (filter << 91n) + (guard << 92n)
    + (scope << 95n));
}

/** `SkillSheetTrait::new`: its holding `REGENERATION` entry's values, if any. */
function skillSheet(row) {
  const entries = [0, 1, 2].map((i) => row.slice(11 + 12 * i, 23 + 12 * i));
  const regen = entries.find((e) => e[0] === 5);
  return {
    id: row[0], kind: row[3], energy: row[4], profession: row[1], adrenaline: row[5],
    activation: row[6], recharge: row[7], regen0: regen ? regen[2] : 0, regen12: regen ? regen[3] : 0,
    range: row[8], entry1: entryBits(entries[0]), entry2: entryBits(entries[1]),
    entry3: entryBits(entries[2]),
  };
}

/** `CasteSheetTrait::new`. */
function casteSheet(row) {
  const vs = row.slice(6, 15).reduce((acc, v, i) => acc + (b(v) << b(6 * i)), 0n);
  return {
    id: row[0], health: row[3], health_regen: row[4], energy: row[20], energy_regen: row[21],
    weapon_ticks: row[18], skills: row.slice(22, 26), armor: row[5], armor_vs: vs,
    weapon: row[15], weapon_damage: row[16], damage_type: row[17], weapon_range: row[19],
    rank: row[26],
  };
}

const CONTENT = {
  skills: [...SKILLS.values()].map(skillSheet),
  potions: [],
  castes: [...CASTES.values()].map(casteSheet),
};
const SHEETS = indexSheets(CONTENT);

// ---- the adventurer: level 1, as `create_adventurer` and `set_build` would make it

/** design/03's profession table (`types::profession`): energy, regeneration pips, armor. */
const PROFESSIONS = {
  1: { name: "Vanguard", energy: 20, regen: 2, armor: 80 },
  2: { name: "Warden", energy: 25, regen: 3, armor: 70 },
  3: { name: "Arcanist", energy: 30, regen: 4, armor: 60 },
};
/**
 * The starter weapons this lot proposes (design/15 *Weapons*, a common one at requirement 0, so its
 * requirement is met at rank 0; design/04: the class's damage type): weapon class, damage, ticks,
 * range, damage type. `BASE` lays out none of these yet (D-158): see the report.
 */
const WEAPONS = {
  1: { class: 2, damage: 9, ticks: 1, range: 1, type: 1 }, // the axe: slashing
  2: { class: 4, damage: 11, ticks: 2, range: 6, type: 2 }, // the bow: piercing
};
const LEVEL = 1;
const at = process.argv.indexOf("--goblins");
const ONLY = at === -1 ? 5 : Number(process.argv[at + 1]);
const MAX_HEALTH = 100 + 20 * (LEVEL - 1);
const MEMBER = { x: 0, y: 7 }; // the gate zone's entry: chunk 0, tile 105 (row 7, column 0)

function memberWords(profession) {
  const p = PROFESSIONS[profession];
  const kit = KITS.get(profession);
  const w = kit[1] === 0 ? { class: 0, damage: 0, ticks: 0, range: 0, type: 0 } : WEAPONS[profession];
  // Level 1 has no attribute point (design/03: 5 a level from 2): every rank 0; the strength cap
  // is 0 until BAL-01's curve (DS-9), so a weapon's strength is 0.
  const low = b(MAX_HEALTH) + (b(p.energy) << 16n) + (b(p.regen) << 24n) + (10n << 32n)
    + (b(LEVEL) << 64n) + (b(profession) << 72n) + (b(w.class) << 88n) + (b(w.damage) << 96n)
    + (b(w.ticks) << 104n) + (b(w.range) << 112n);
  const high = (b(w.type) << 32n) + ((w.class === 0 ? 0n : 1n) << 48n);
  const skills = kit.slice(2, 8);
  const bar = skills.reduce((acc, s, i) => acc + (b(s) << b(16 * i)), 0n);
  const armor = b(p.armor) & 0xffffn;
  return {
    state: LIVE + 1n + (b(MEMBER.x) << 32n) + (b(MEMBER.y) << 40n) + (b(MAX_HEALTH) << 64n)
      + (b(p.energy * 3) << 80n),
    timers: LIVE + 255n,
    effects: LIVE,
    recharges: LIVE,
    stats: LIVE + low + (high << 128n),
    bar: LIVE + bar + ((255n + (armor << 104n)) << 128n),
    kit: LIVE,
  };
}

// ---- the gate pack: `PACK` 5 at the gate zone's level (its Heart takes `level_max`)

const ENGAGED = 3;
const DEAD = 6;
const GATE_ZONE = 5;
const gatePack = QUOTAS.find((q) => q[0] === GATE_ZONE)[2];
const gateLevel = LOCATIONS.get(GATE_ZONE)[5];
/** Where the pack stands: 5 tiles in from the entry, its goblins within 2 of its tile. */
const SPOTS = [[5, 7], [6, 6], [6, 8], [5, 5], [5, 9]];

function goblinWords() {
  const row = PACKS.get(gatePack);
  const castes = [];
  for (let i = 0; i < 5; i++) {
    const [caste, min] = [row[1 + 3 * i], row[2 + 3 * i]];
    for (let k = 0; k < min; k++) castes.push(caste);
  }
  return castes.slice(0, ONLY).map((caste, k) => {
    const sheet = CASTES.get(caste);
    const health = Math.floor(((80 + 20 * gateLevel) * sheet[3]) / 100);
    const [x, y] = SPOTS[k];
    return {
      entity: 8 + k, // chunk 0's pack 0, goblin k (`8 + 16 chunk + k`)
      awake: true,
      state: LIVE + b(x) + (b(y) << 8n) + (b(ENGAGED) << 24n) + (b(health) << 32n)
        + (b(sheet[20] * 3) << 48n) + (b(caste) << 64n) + (b(gateLevel) << 80n),
      timers: LIVE + 255n,
    };
  });
}

// ---- the fight

const TILES = (1n << 225n) - 1n;
const AREA = { width: 1, height: 1, known: 1n, revealed: 1n, chunks: [[0, TILES]], changed: [], ran: false };

/** One action through `runSegment`; `undefined` when it is refused or plays nothing. */
function play(words, ground, action) {
  const segment = {
    words, content: CONTENT, area: AREA, level: gateLevel, ground, owed: 0, weight: 255, actions: [action],
  };
  const ran = runSegment(segment, CLASSES);
  if (ran.done.illegal !== undefined || ran.done.played === 0) return undefined;
  return ran;
}

const skill = (slot, value, tile = false) => ({ kind: "skill", slot, target: { tile, value } });

/**
 * The autopilot's priority list for `profession`, given the world: the first legal one is played.
 * Slots are the kit's order (`KIT` row): Vanguard Cleave, Rending Cut, Skullring, Second Wind,
 * Brace, Warcry; Warden Aimed Shot, Hamstring Shot, Venom Coat, Snare, Field Dressing, Sidestep;
 * Arcanist Ember Bolt, Cinder Ring, Rime Shard, Stone Skin, Static Lash, Deep Draw.
 */
function choices(profession, world, target, adjacent, step) {
  const me = world.members[0];
  const low = me.health * 2 < MAX_HEALTH;
  const foe = target.entity;
  const list = [];
  if (profession === 1) {
    if (low) list.push(skill(3, 0));
    list.push(skill(5, 0), skill(2, foe), skill(0, foe), skill(1, foe));
    if (adjacent >= 2) list.push(skill(4, 0));
    list.push({ kind: "attack", entity: foe });
  } else if (profession === 2) {
    if (low) list.push(skill(4, 0));
    if (adjacent >= 1) list.push(skill(5, 0));
    list.push(skill(2, 0), skill(1, foe), skill(0, foe), { kind: "attack", entity: foe });
  } else {
    if (adjacent >= 2) list.push(skill(1, 0));
    list.push(skill(3, 0), skill(5, 0), skill(2, foe), skill(4, foe), skill(0, foe));
  }
  if (step !== undefined) list.push({ kind: "move", direction: step });
  list.push({ kind: "wait" });
  return list;
}

function fight(profession) {
  let words = { clock: 0, members: [memberWords(profession)], goblins: goblinWords(), killed: [], defeated: false };
  let ground = [];
  const counts = new Map();
  for (let turn = 0; turn < 2000; turn++) {
    const world = loadWorld(words, SHEETS);
    const me = world.members[0];
    const alive = world.goblins.filter((g) => g.ai !== DEAD);
    if (words.defeated || me.health === 0 || alive.length === 0) break;
    const at = memberPlace(me);
    const origin = board(at.x, at.y);
    const from = position(origin, at.x, at.y);
    const placed = alive.map((g) => {
      const p = goblinPlace(g);
      return { goblin: g, to: position(origin, p.x, p.y) };
    });
    placed.sort((l, r) => distance(from, l.to) - distance(from, r.to));
    const nearest = placed[0];
    const adjacent = placed.filter((p) => distance(from, p.to) === 1).length;
    const step = distance(from, nearest.to) > 1 ? facing(from, nearest.to, 0) : undefined;
    let ran;
    for (const action of choices(profession, world, nearest.goblin, adjacent, step)) {
      ran = play(words, ground, action);
      if (ran !== undefined) {
        const name = action.kind === "skill" ? `skill ${action.slot}` : action.kind;
        counts.set(name, (counts.get(name) ?? 0) + 1);
        break;
      }
    }
    if (ran === undefined) throw new Error(`${PROFESSIONS[profession].name}: no legal action at clock ${words.clock}`);
    words = ran.words;
    ground = ran.ground;
  }
  const world = loadWorld(words, SHEETS);
  const me = world.members[0];
  const left = world.goblins.filter((g) => g.ai !== DEAD);
  return {
    profession: PROFESSIONS[profession].name,
    win: left.length === 0 && me.health > 0 && !words.defeated,
    ticks: words.clock,
    health: me.health,
    max_health: MAX_HEALTH,
    goblins_left: left.length,
    goblin_health_left: left.reduce((sum, g) => sum + g.health, 0),
    actions: Object.fromEntries(counts),
  };
}

const results = [1, 2, 3].map(fight);
const pack = PACKS.get(gatePack);
console.log(`gate pack: PACK ${gatePack} (${pack.slice(1, 16)}), level ${gateLevel}, its first ${ONLY} goblins`);
for (const r of results) {
  const outcome = r.win ? "WINS" : "LOSES";
  console.log(
    `${r.profession.padEnd(9)} ${outcome} in ${r.ticks} ticks, health ${r.health}/${r.max_health}, `
      + `goblins left ${r.goblins_left} (health ${r.goblin_health_left}); actions ${JSON.stringify(r.actions)}`,
  );
}
console.log(JSON.stringify(results));
