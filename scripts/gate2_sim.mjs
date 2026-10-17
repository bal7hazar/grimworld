#!/usr/bin/env node
// CNT-01's fight check (D-309 item 5, D-310 item 1): each MVP profession at level 1, with its kit
// (the six starter skills of `contracts/seed/test-region.json`'s `KIT` row), against the gate pack
// (`PACK` 5, the Heart of the gate zone, `LOCATION` 5), fought on track CV's mirror of the tick
// (`client/sim`), over `--seeds` placements of the pack. Prints, per case and profession, the wins,
// the ticks and the health left (mean and worst), then a JSON line.
//
//   node scripts/gate2_sim.mjs [--seeds N] [--goblins N]
//
// (after `pnpm install --frozen-lockfile`, for @scure/starknet). `--goblins N` fights the pack's
// first N goblins only. The cases:
// - weapons `inert`, as the chain was before WPN-01 (`Build::loadout` passed weapon 0), or `kit`, as
//   the chain is since WPN-01: the kit's weapon, its `BASE` row of the seed at requirement 0 (met),
//   and CBT-05f's weapon-required bit on each bar attack of another attribute than the weapon's;
// - ranks `today` (a caste's one rank, design/20 §2.2), `a` (D-310 (a): a goblin's rank follows its
//   level, rank 0 at level 1, the gate pack's level) or `a+b` (and (b): rank 1 in the profession's
//   primary attribute at creation).
// A seed draws what the entry draw decides of a Heart in a 1 × 1 zone: the pack's tile (at least 3
// from the entry), its goblins' tiles (within 2 of it) and their alert (asleep or watching).
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
const { neighbor } = await import(new URL("window.ts", SRC).href);
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
const BASES = byId(rows("bases", 10));
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

// ---- the adventurer: level 1, as `create_adventurer` and `set_build` make it (`build.cairo`'s
// flattening of an empty build: no attribute point at level 1, design/03)

/** design/03's profession table (`types::profession`) and the flattening's class terms (DS-7): energy
 * and regeneration with light armor's +20 and +1 for the Arcanist, the innate armor per type
 * (heavy +20 against types 1–3, medium +30 against 4–7), armor, the primary attribute's id. */
const PROFESSIONS = {
  1: { name: "Vanguard", energy: 20, regen: 2, armor: 80, vs: [20, 20, 20, 0, 0, 0, 0, 0, 0], primary: 1 },
  2: { name: "Warden", energy: 25, regen: 3, armor: 70, vs: [0, 0, 0, 30, 30, 30, 30, 0, 0], primary: 6 },
  3: { name: "Arcanist", energy: 50, regen: 5, armor: 60, vs: [0, 0, 0, 0, 0, 0, 0, 0, 0], primary: 10 },
};
/** The kit's weapon as `create_adventurer` creates it and `set_build` flattens it (WPN-01): its
 * `BASE` row (slot, hands, class, damage at requirement 0 and 9, ticks, range, damage type,
 * attribute) at requirement 0. */
function kitWeapon(base) {
  const [, , , klass, damage0, , ticks, range, type, attribute] = BASES.get(base);
  return { class: klass, damage: damage0, ticks, range, type, attribute };
}
const INERT = { class: 0, damage: 0, ticks: 0, range: 0, type: 0, attribute: 0 };
const ATTACK = 1;
const WELLSPRING_ENERGY_PER_RANK = 3;
const LEVEL = 1;
const MAX_HEALTH = 100 + 20 * (LEVEL - 1);
const ENTRY = { x: 0, y: 7 }; // the gate zone's entry: chunk 0, tile 105 (row 7, column 0)

const flag = (name, otherwise) => {
  const at = process.argv.indexOf(name);
  return at === -1 ? otherwise : Number(process.argv[at + 1]);
};
const SEEDS = flag("--seeds", 20);
const ONLY = flag("--goblins", 5);

function memberWords(profession, weapons, primaryRank) {
  const p = PROFESSIONS[profession];
  const kit = KITS.get(profession);
  const w = weapons === "kit" && kit[1] !== 0 ? kitWeapon(kit[1]) : INERT;
  const skills = kit.slice(2, 8);
  // CBT-05f, live since WPN-01 (`FlattenTrait::mappings`): an attack slot of another attribute than
  // the weapon's is bound to a weapon it does not hold. Before WPN-01 the loadout named no attack.
  const required = weapons === "kit"
    ? skills.reduce((acc, s, i) => {
      const row = SKILLS.get(s);
      return row !== undefined && row[3] === ATTACK && row[2] !== w.attribute ? acc | (1 << i) : acc;
    }, 0)
    : 0;
  const energy = p.energy + (profession === 3 ? WELLSPRING_ENERGY_PER_RANK * primaryRank : 0);
  // The rank of each bar skill's attribute (`MemberStats.ranks`, 4 bits a slot): the primary's.
  const ranks = skills.reduce(
    (acc, s, i) => acc + (SKILLS.get(s)[2] === p.primary ? b(primaryRank) << b(4 * i) : 0n), 0n);
  const [v1, v2, v3, v4, v5, v6, v7, v8, v9] = p.vs.map(b);
  const low = b(MAX_HEALTH) + (b(energy) << 16n) + (b(p.regen) << 24n) + (10n << 32n) + (b(required) << 40n)
    + (v1 << 48n) + (v2 << 54n) + (b(LEVEL) << 64n) + (b(profession) << 72n)
    + (b(primaryRank) << 80n) + (b(w.class) << 88n) + (b(w.damage) << 96n) + (b(w.ticks) << 104n)
    + (b(w.range) << 112n);
  const high = ranks + (b(w.type) << 32n) + ((w.class === 0 ? 0n : 1n) << 48n) + (v3 << 72n)
    + (v4 << 78n) + (v5 << 84n) + (v6 << 90n) + (v7 << 96n) + (v8 << 102n) + (v9 << 108n);
  const bar = skills.reduce((acc, s, i) => acc + (b(s) << b(16 * i)), 0n);
  return {
    state: LIVE + 1n + (b(ENTRY.x) << 32n) + (b(ENTRY.y) << 40n) + (b(MAX_HEALTH) << 64n)
      + (b(energy * 3) << 80n),
    timers: LIVE + 255n,
    effects: LIVE,
    recharges: LIVE,
    stats: LIVE + low + (high << 128n),
    bar: LIVE + bar + ((255n + ((b(p.armor) & 0xffffn) << 104n)) << 128n),
    kit: LIVE,
  };
}

// ---- the gate pack: `PACK` 5 at the gate zone's level (its Heart takes `level_max`)

const DEAD = 6;
const GATE_ZONE = 5;
const gatePack = QUOTAS.find((q) => q[0] === GATE_ZONE)[2];
const gateLevel = LOCATIONS.get(GATE_ZONE)[5];

/** mulberry32: a seed's draws, reproducible. */
function rng(seed) {
  let a = seed >>> 0;
  return (n) => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (((t ^ (t >>> 14)) >>> 0) % n);
  };
}

/** The hex distance between two tiles of the location (axial `q = x − ⌊y / 2⌋`, `r = y`). */
function hex(a, b2) {
  const dq = (a.x - Math.floor(a.y / 2)) - (b2.x - Math.floor(b2.y / 2));
  const dr = a.y - b2.y;
  return (Math.abs(dq) + Math.abs(dr) + Math.abs(dq + dr)) / 2;
}

const CHUNK = [];
for (let y = 0; y < 15; y++) for (let x = 0; x < 15; x++) CHUNK.push({ x, y });

/** The pack of seed `seed`: its tile at least 3 from the entry, its goblins on distinct tiles within
 * 2 of it, each asleep or watching. */
function goblinWords(seed, rankAtLevel) {
  const draw = rng(seed);
  const tiles = CHUNK.filter((t) => hex(t, ENTRY) >= 3);
  const centre = tiles[draw(tiles.length)];
  const near = CHUNK.filter((t) => hex(t, centre) <= 2 && hex(t, centre) > 0 && hex(t, ENTRY) >= 3);
  const spots = [centre];
  while (spots.length < 5) {
    const t = near.splice(draw(near.length), 1)[0];
    spots.push(t);
  }
  const row = PACKS.get(gatePack);
  const castes = [];
  for (let i = 0; i < 5; i++) {
    const [caste, min] = [row[1 + 3 * i], row[2 + 3 * i]];
    for (let k = 0; k < min; k++) castes.push(caste);
  }
  return castes.slice(0, ONLY).map((caste, k) => {
    const sheet = CASTES.get(caste);
    const health = Math.floor(((80 + 20 * gateLevel) * sheet[3]) / 100);
    const { x, y } = spots[k];
    return {
      entity: 8 + k, // chunk 0's pack 0, goblin k (`8 + 16 chunk + k`)
      awake: false,
      state: LIVE + b(x) + (b(y) << 8n) + (b(draw(2)) << 24n) + (b(health) << 32n)
        + (b(sheet[20] * 3) << 48n) + (b(caste) << 64n) + (b(gateLevel) << 80n),
      timers: LIVE + 255n,
    };
  });
}

// ---- the fight

const TILES = (1n << 225n) - 1n;
const AREA = { width: 1, height: 1, known: 1n, revealed: 1n, chunks: [[0, TILES]], changed: [], ran: false };
/** (a): the caste sheets with every rank at the gate pack's level's, 0 at level 1. */
const AT_LEVEL = { ...CONTENT, castes: CONTENT.castes.map((c) => ({ ...c, rank: 0 })) };

/** One action through `runSegment`; `undefined` when it is refused or plays nothing. */
function play(content, words, ground, action) {
  const segment = {
    words, content, area: AREA, level: gateLevel, ground, owed: 0, weight: 255, actions: [action],
  };
  const ran = runSegment(segment, CLASSES);
  if (ran.done.illegal !== undefined || ran.done.played === 0) return undefined;
  return ran;
}

const skill = (slot, value) => ({ kind: "skill", slot, target: { tile: false, value } });
const AXIAL = [[-1, 0], [-1, 1], [0, 1], [1, 0], [1, -1], [0, -1]];

/** The six moves, nearest to `to` first (location tiles, the axial approximation of `hex`). */
function steps(at, to) {
  const q = at.x - Math.floor(at.y / 2);
  return AXIAL.map(([dq, dr], direction) => {
    const y = at.y + dr;
    return { direction, d: hex({ x: q + dq + Math.floor(y / 2), y }, to) };
  }).sort((l, r) => l.d - r.d).map((m) => ({ kind: "move", direction: m.direction }));
}

/**
 * The autopilot's priority list for `profession`: the first legal one is played. Slots are the
 * kit's order (`KIT` row): Vanguard Cleave, Gash, Haft Blow, Second Wind, Brace, Warcry; Warden
 * Aimed Shot, Hamstring Shot, Venom Coat, Snare, Field Dressing, Sidestep; Arcanist Ember Bolt,
 * Cinder Ring, Rime Shard, Stone Skin, Static Lash, Deep Draw. Snare (a tile) is not used.
 */
function choices(profession, me, foe, adjacent, far) {
  const low = me.health * 2 < MAX_HEALTH;
  const list = [];
  if (profession === 1) {
    if (low) list.push(skill(3, 0));
    if (adjacent >= 2) list.push(skill(4, 0));
    list.push(skill(5, 0), skill(2, foe), skill(0, foe), skill(1, foe), { kind: "attack", entity: foe });
  } else if (profession === 2) {
    if (low) list.push(skill(4, 0));
    if (adjacent >= 1) list.push(skill(5, 0));
    list.push(skill(2, 0), skill(1, foe), skill(0, foe), { kind: "attack", entity: foe });
  } else {
    if (adjacent >= 2) list.push(skill(1, 0));
    list.push(skill(3, 0), skill(5, 0), skill(2, foe), skill(4, foe), skill(0, foe));
  }
  return [...list, ...far, { kind: "wait" }];
}

function fight(profession, seed, weapons, ranks) {
  const content = ranks === "today" ? CONTENT : AT_LEVEL;
  const sheets = indexSheets(content);
  const primary = ranks === "a+b" ? 1 : 0;
  let words = {
    clock: 0,
    members: [memberWords(profession, weapons, primary)],
    goblins: goblinWords(seed, ranks !== "today"),
    killed: [],
    defeated: false,
  };
  let ground = [];
  for (let turn = 0; turn < 600; turn++) {
    const world = loadWorld(words, sheets);
    const me = world.members[0];
    const alive = world.goblins.filter((g) => g.ai !== DEAD);
    if (words.defeated || me.health === 0 || alive.length === 0) break;
    const at = memberPlace(me);
    const near = alive.map((g) => ({ goblin: g, d: hex(at, goblinPlace(g)), at: goblinPlace(g) }));
    near.sort((l, r) => l.d - r.d);
    const adjacent = near.filter((n) => n.d === 1).length;
    const far = near[0].d > 1 ? steps(at, near[0].at) : [];
    let ran;
    for (const action of choices(profession, me, near[0].goblin.entity, adjacent, far)) {
      ran = play(content, words, ground, action);
      if (ran !== undefined) break;
    }
    if (ran === undefined) throw new Error(`no legal action at clock ${words.clock}`);
    words = ran.words;
    ground = ran.ground;
  }
  const world = loadWorld(words, sheets);
  const me = world.members[0];
  const left = world.goblins.filter((g) => g.ai !== DEAD);
  return { win: left.length === 0 && me.health > 0 && !words.defeated, ticks: words.clock, health: me.health };
}

const mean = (xs) => Math.round((10 * xs.reduce((s, x) => s + x, 0)) / xs.length) / 10;
const results = [];
const pack = PACKS.get(gatePack);
console.log(`gate pack: PACK ${gatePack} (${pack.slice(1, 16)}), level ${gateLevel}, its first ${ONLY} goblins, ${SEEDS} seeds`);
for (const weapons of ["inert", "kit"]) {
  for (const ranks of ["today", "a", "a+b"]) {
    for (const profession of [1, 2, 3]) {
      const runs = [];
      for (let seed = 1; seed <= SEEDS; seed++) runs.push(fight(profession, seed, weapons, ranks));
      const r = {
        weapons, ranks, profession: PROFESSIONS[profession].name,
        wins: runs.filter((x) => x.win).length, seeds: SEEDS,
        ticks_mean: mean(runs.map((x) => x.ticks)), ticks_worst: Math.max(...runs.map((x) => x.ticks)),
        health_mean: mean(runs.map((x) => x.health)), health_worst: Math.min(...runs.map((x) => x.health)),
      };
      results.push(r);
      console.log(
        `weapons ${weapons.padEnd(5)} ranks ${ranks.padEnd(5)} ${r.profession.padEnd(9)} wins ${r.wins}/${SEEDS}, `
          + `ticks mean ${r.ticks_mean} worst ${r.ticks_worst}, health mean ${r.health_mean} worst ${r.health_worst}/${MAX_HEALTH}`,
      );
    }
  }
}
console.log(JSON.stringify(results));
