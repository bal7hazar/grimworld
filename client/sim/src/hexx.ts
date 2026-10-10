// What the reveal (ENG-05) calls of `hexx` 0.2.0, the Cairo dependency of `grimworld_logic`: the
// draws (`board/rng.cairo`, `RngTrait`), the automaton with margins (`generators/caver.cairo`,
// `CaverTrait::smooth`, N-1) and the flood of one component (`CaverTrait::keep_component`,
// `finders/bfs.cairo`). The rules, their edges and their reasons are `hexx`'s documentation; this
// file names only where the mirror computes differently.
//
// A bitmap is a `bigint`, bit `W row + column`. Where `hexx` computes in the field (a neighbour
// plane is a product by a power of two, a shift down a product by its inverse), the mirror does the
// same products modulo `P`, so that a value that is not exact in Cairo is not exact here either.
// The automaton's rule runs on the whole bitmap where `hexx` runs it per `u128` limb: every
// operation of the rule is bitwise or a sum of disjoint sets, so no carry crosses bit 128 and the
// two are equal. The flood is a breadth-first search tile by tile, where `hexx` dilates limbs: it
// returns the same set, the component of the source.

import { poseidonSmall } from "@scure/starknet";
import { P, feltArg, panic } from "./felt";

const LOW = 2n ** 128n - 1n;
const TWO_POW_64 = 2n ** 64n;

/** A felt of the field: `value` modulo `P`, never negative. */
export function felt(value: bigint): bigint {
  const rest = value % P;
  return rest < 0n ? rest + P : rest;
}

/** `a^e` modulo `P`. */
function power(a: bigint, e: bigint): bigint {
  let result = 1n;
  let base = felt(a);
  for (let rest = e; rest > 0n; rest >>= 1n) {
    if (rest & 1n) result = (result * base) % P;
    base = (base * base) % P;
  }
  return result;
}

/** `1 / a` in the field (`a` not 0). */
export function inverse(a: bigint): bigint {
  return power(a, P - 2n);
}

/** `hades_permutation(a, b, c)`: Poseidon's permutation of the state, `@scure/starknet`'s. */
export function hades(a: bigint, b: bigint, c: bigint): [bigint, bigint, bigint] {
  const [x, y, z] = poseidonSmall([feltArg(a), feltArg(b), feltArg(c)]);
  return [x!, y!, z!];
}

/** `Bits::pow`: `2^i`. */
export function pow(i: number): bigint {
  return 1n << BigInt(i);
}

/** `Bits::get`: bit `index` of `bits`. */
export function has(bits: bigint, index: number): boolean {
  return ((bits >> BigInt(index)) & 1n) === 1n;
}

/** `Bits::popcount`: the set bits. */
export function popcount(bits: bigint): number {
  let count = 0;
  for (let rest = bits; rest > 0n; rest >>= 1n) count += Number(rest & 1n);
  return count;
}

/** The index of the `n`-th set bit of `bits` (`n` below the count; Cairo has no such call). */
export function nth(bits: bigint, n: number): number {
  let left = n;
  let index = 0;
  for (let rest = bits; rest > 0n; rest >>= 1n, index++) {
    if (rest & 1n) {
      if (left === 0) return index;
      left--;
    }
  }
  throw new RangeError(`no set bit ${n} in ${bits}`);
}

/** `Bits::to_felt` of a `u256` that came from a felt: `low + high × 2^128` in the field. */
export function toFelt(bits: bigint): bigint {
  return felt(bits);
}

// ---- The draws (`RngTrait`) -------------------------------------------------------------------

/** `hexx`'s `Rng`: a seed and a pool of draws, refilled from the seed's permutation. */
export type Rng = { seed: bigint; pool: bigint };

export function rngNew(seed: bigint): Rng {
  return { seed: feltArg(seed), pool: 0n };
}

/** `RngTrait::mix`: the first felt of `hades(lhs, rhs, 2)`. */
export function mix(lhs: bigint, rhs: bigint): bigint {
  return hades(lhs, rhs, 2n)[0];
}

/** `RngTrait::refill`: the seed's permutation, its first felt the next seed, the second's low limb the pool. */
function refill(rng: Rng): void {
  const [seed, word] = hades(rng.seed, 0n, 2n);
  rng.seed = seed;
  rng.pool = word & LOW;
}

/** `RngTrait::draw` (and `draw6`, `draw_byte`): the pool's remainder by `bound`, refilled below 2^64. */
export function draw(rng: Rng, bound: number): number {
  if (bound <= 0) throw new RangeError(`a NonZero bound is not ${bound}`);
  if (rng.pool < TWO_POW_64) refill(rng);
  const b = BigInt(bound);
  const value = rng.pool % b;
  rng.pool = rng.pool / b;
  return Number(value);
}

// ---- The automaton with margins (`CaverTrait::smooth`, N-1) ----------------------------------

const INV_2 = inverse(2n);

/** `CaverInternal::margins`: the constants of a `width × height` board, rows of parity `odd`. */
function margins(width: number, height: number, odd: boolean) {
  const row = pow(width);
  const down = inverse(row);
  const board = pow(width * height);
  const upEven = felt(row * INV_2);
  const pair = felt(row * row - 1n);
  let first: bigint;
  let second: bigint;
  if (height % 2 === 0) {
    first = felt((board - 1n) * inverse(pair));
    second = felt(first * row);
  } else {
    first = felt((board * row - 1n) * inverse(pair));
    second = felt((first - 1n) * down);
  }
  const top = felt(board * down);
  const [even, other] = odd ? [second, first] : [first, second];
  return {
    odd,
    board: board - 1n,
    interior: felt((first + second - 1n - top) * (upEven - 2n)),
    bottom: row - 1n,
    evens: felt(even * (row - 2n)),
    odds: felt(other * (upEven - 1n)),
    upEven,
    upOdd: row,
    upWide: felt(row + row),
    downEven: felt(down * INV_2),
    downOdd: down,
    downWide: felt(down + down),
  };
}

type Margins = ReturnType<typeof margins>;

/** `CaverInternal::freeze`: the part of the six neighbour planes that the frozen tiles give. */
function freeze(m: Margins, tiles: bigint) {
  const even = tiles & m.evens;
  const odd = tiles & m.odds;
  const down = felt(tiles - (tiles & m.bottom));
  const [downEven, downOdd] = m.odd
    ? [even, felt(odd - (odd & m.bottom))]
    : [felt(even - (even & m.bottom)), odd];
  return {
    tiles,
    east: felt(tiles + tiles),
    west: felt(down * INV_2),
    north: felt(down * m.downOdd),
    northOther: felt(downOdd * m.downWide + downEven * m.downEven),
    south: felt(tiles * m.upOdd),
    southOther: felt(odd * m.upWide + even * m.upEven),
  };
}

/** `CaverInternal::rule`, `B4/S2`: born with 4 floor neighbours or more, survives with 2 or more. */
function rule(grid: bigint, a: bigint, b: bigint, c: bigint, d: bigint, e: bigint, f: bigint) {
  const ab = a & b;
  const x = a ^ b;
  const xc = x & c;
  const s1 = x ^ c;
  const de = d & e;
  const y = d ^ e;
  const yf = y & f;
  const s2 = y ^ f;
  const c3 = s1 & s2;
  const c12 = (ab + xc) & (de + yf);
  const x12 = (ab + xc) ^ (de + yf);
  const x3 = x12 & c3;
  const b1 = x12 ^ c3;
  const survive = grid & b1;
  return (c12 + x3) | survive;
}

/** `CaverInternal::step_frozen`: one generation on the free tiles. */
function stepFrozen(m: Margins, frozen: ReturnType<typeof freeze>, free: bigint, grid: bigint) {
  const value = toFelt(grid);
  const gridEven = grid & m.evens;
  const gridOdd = felt(value - gridEven);
  const next = rule(
    grid,
    felt(value + value + frozen.east),
    felt(value * INV_2 + frozen.west),
    felt(value * m.downOdd + frozen.north),
    felt(gridOdd * m.downWide + gridEven * m.downEven + frozen.northOther),
    felt(value * m.upOdd + frozen.south),
    felt(gridOdd * m.upWide + gridEven * m.upEven + frozen.southOther),
  );
  return next & free;
}

/**
 * `CaverTrait::smooth`: `order` generations of the automaton on `grid`, the ring and the tiles of
 * `held` keeping their value, each row with its global parity (`odd`: local row 0 is globally odd).
 */
export function smooth(
  grid: bigint,
  width: number,
  height: number,
  order: number,
  held: bigint,
  odd: boolean,
): bigint {
  if (width <= 2 || height <= 2) panic("Asserter: invalid dimension");
  if (width * (height + 1) + 1 > 251) panic("Caver: dimensions too large");
  const m = margins(width, height, odd);
  if (order === 0) return grid & m.board;
  const free = m.interior - (held & m.interior);
  const kept = m.board - free;
  const frozen = freeze(m, toFelt(grid & kept));
  let free_grid = grid & free;
  for (let generation = 0; generation < order; generation++) {
    free_grid = stepFrozen(m, frozen, free, free_grid);
  }
  return felt(toFelt(free_grid) + frozen.tiles);
}

// ---- The component of one tile (`CaverTrait::keep_component`) -------------------------------

/** The hex neighbours of `(x, y)` on a board whose row 0 is even (`hexx`'s layout, `+1` West). */
function around(x: number, y: number): [number, number][] {
  const shift = y % 2 === 0 ? -1 : 0;
  return [
    [x + 1, y],
    [x - 1, y],
    [x + shift, y + 1],
    [x + shift + 1, y + 1],
    [x + shift, y - 1],
    [x + shift + 1, y - 1],
  ];
}

/**
 * `CaverTrait::keep_component`: the floor tiles of `grid`'s interior connected to `from`, a floor
 * tile, on a `width × height` board.
 */
export function keep_component(grid: bigint, width: number, height: number, from: number): bigint {
  if (!has(grid, from)) panic("Caver: position not floor");
  if (width <= 2 || height <= 2) panic("Asserter: invalid dimension");
  const free = (x: number, y: number): boolean =>
    x > 0 && x < width - 1 && y > 0 && y < height - 1 && has(grid, y * width + x);
  let kept = 0n;
  const queue: [number, number][] = [[from % width, Math.floor(from / width)]];
  if (free(...queue[0]!)) kept |= pow(from);
  while (queue.length > 0) {
    const [x, y] = queue.shift()!;
    for (const [nx, ny] of around(x, y)) {
      const tile = ny * width + nx;
      if (free(nx, ny) && !has(kept, tile)) {
        kept |= pow(tile);
        queue.push([nx, ny]);
      }
    }
  }
  return kept;
}
