// The TypeScript mirror of spikes/SPK-4/cairo (option a): the same functions, the same order of
// operations, the same types, on the helpers of cairo.ts.

import {
  CairoPanic,
  add,
  div,
  felt,
  feltAdd,
  feltSub,
  fromFelt,
  i16,
  i32,
  mul,
  narrow,
  sub,
  u16,
  u32,
  u8,
} from "./cairo.ts";
import { POW2_X40 } from "./table.ts";

const X_LOW = -160n;
const X_HIGH = 80n;
const SHIFT = 65536n;

/** design/04 *Damage formula*; spikes/SPK-4/cairo/src/damage.cairo. */
export function damage(
  base: bigint,
  strength: bigint,
  armor: bigint,
  bonus: bigint,
  penetration: bigint,
  modifier: bigint,
): bigint {
  const effective = sub(u16, add(u16, armor, bonus), penetration);
  let x = sub(i32, strength, effective);
  x = x < X_LOW ? X_LOW : x > X_HIGH ? X_HIGH : x;
  const factor = POW2_X40[Number(x - X_LOW)];
  const raw = narrow(i32, div(u32, mul(u32, base, factor), SHIFT));
  const total = add(i32, raw, div(i32, mul(i32, raw, modifier), 100n));
  return narrow(u16, total);
}

const WIDTH = 15n;
const HEIGHT = 16n;
const TILES = 240n;

const has = (layer: bigint, tile: bigint): boolean => ((layer >> tile) & 1n) === 1n;

function axial(tile: bigint): [bigint, bigint] {
  const row = tile / WIDTH;
  const col = tile % WIDTH;
  return [sub(i16, col, row / 2n), row];
}

const abs = (x: bigint): bigint => (x < 0n ? -x : x);

/** Hex distance on the window; spikes/SPK-4/cairo/src/board.cairo. */
export function distance(a: bigint, b: bigint): bigint {
  const [qa, ra] = axial(a);
  const [qb, rb] = axial(b);
  const dq = sub(i16, qa, qb);
  const dr = sub(i16, ra, rb);
  const d = div(i16, add(i16, add(i16, abs(dq), abs(dr)), abs(add(i16, dq, dr))), 2n);
  return narrow(u8, d);
}

/** One goblin step; spikes/SPK-4/cairo/src/board.cairo. */
export function goblinStep(
  walkable: bigint,
  occupied: bigint,
  goblin: bigint,
  target: bigint,
): [bigint, bigint] {
  if (!(goblin < TILES && target < TILES)) throw new CairoPanic(felt("board: tile outside window"));
  const here = distance(goblin, target);
  if (here <= 1n) return [goblin, occupied];
  const row = goblin / WIDTH;
  const col = goblin % WIDTH;
  let best = goblin;
  let bestD = here;
  const consider = (n: bigint): void => {
    if (!has(walkable, n) || has(occupied, n)) return;
    const d = distance(n, target);
    if (d < bestD || (d === bestD && best !== goblin && n < best)) {
      best = n;
      bestD = d;
    }
  };
  if (col + 1n < WIDTH) consider(goblin + 1n);
  if (col > 0n) consider(goblin - 1n);
  const odd = row % 2n === 1n;
  const [leftOk, rightOk, left, right] = odd
    ? [true, col + 1n < WIDTH, 0n, 1n]
    : [col > 0n, true, 1n, 0n];
  if (row > 0n) {
    const up = goblin - WIDTH;
    if (leftOk) consider(up - left);
    if (rightOk) consider(up + right);
  }
  if (row + 1n < HEIGHT) {
    const down = goblin + WIDTH;
    if (leftOk) consider(down - left);
    if (rightOk) consider(down + right);
  }
  if (best === goblin) return [goblin, occupied];
  return [best, feltAdd(feltSub(occupied, 1n << goblin), 1n << best)];
}

/** One case, `[op, args...]`, decoded as spikes/SPK-4/cairo/src/exec.cairo does. */
export function run(c: bigint[]): bigint[] {
  const op = c[0];
  if (op === 0n) {
    if (c.length !== 7) throw new CairoPanic(felt("exec: wrong argument count"));
    return [
      damage(
        fromFelt(u16, c[1]),
        fromFelt(u16, c[2]),
        fromFelt(u16, c[3]),
        fromFelt(u16, c[4]),
        fromFelt(u16, c[5]),
        fromFelt(i16, c[6]),
      ),
    ];
  }
  if (op === 1n) {
    if (c.length !== 5) throw new CairoPanic(felt("exec: wrong argument count"));
    const [tile, occ] = goblinStep(c[1], c[2], fromFelt(u8, c[3]), fromFelt(u8, c[4]));
    return [tile, occ];
  }
  throw new CairoPanic(felt("exec: unknown op"));
}
