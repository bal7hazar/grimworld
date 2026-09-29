// Cairo's integer semantics on bigint, as ADR-0003 *What a TypeScript mirror must reproduce* asks:
// every operation is range-checked and throws where Cairo panics; division truncates toward zero;
// felt252 arithmetic is modulo the field prime, for bitmaps only.

/** The Stark field prime. */
export const P = 2n ** 251n + 17n * 2n ** 192n + 1n;

/** A Cairo panic: the felts of its panic data, the first one read as a short string. */
export class CairoPanic extends Error {
  readonly data: bigint[];
  constructor(...data: bigint[]) {
    super(data.map(shortString).join(", "));
    this.data = data;
  }
}

/** A felt as a Cairo short string (`'u16_sub Overflow'`). */
export function shortString(f: bigint): string {
  let s = "";
  for (let x = f; x > 0n; x >>= 8n) s = String.fromCharCode(Number(x & 0xffn)) + s;
  return s;
}

/** A short string as a felt. */
export function felt(s: string): bigint {
  let f = 0n;
  for (const c of s) f = (f << 8n) | BigInt(c.charCodeAt(0));
  return f;
}

type Int = { name: string; min: bigint; max: bigint };

export const u8: Int = { name: "u8", min: 0n, max: 255n };
export const u16: Int = { name: "u16", min: 0n, max: 65535n };
export const u32: Int = { name: "u32", min: 0n, max: 4294967295n };
export const i16: Int = { name: "i16", min: -32768n, max: 32767n };
export const i32: Int = { name: "i32", min: -2147483648n, max: 2147483647n };

function check(t: Int, op: string, v: bigint): bigint {
  if (v < t.min || v > t.max) throw new CairoPanic(felt(`${t.name}_${op} Overflow`));
  return v;
}

export const add = (t: Int, a: bigint, b: bigint): bigint => check(t, "add", a + b);
export const sub = (t: Int, a: bigint, b: bigint): bigint => check(t, "sub", a - b);
export const mul = (t: Int, a: bigint, b: bigint): bigint => check(t, "mul", a * b);

/** Integer division, truncating toward zero (bigint's `/` does). */
export function div(t: Int, a: bigint, b: bigint): bigint {
  if (b === 0n) throw new CairoPanic(felt("Division by 0"));
  return check(t, "div", a / b);
}

/** `TryInto::try_into(..).unwrap()` between integer types. */
export function narrow(t: Int, v: bigint): bigint {
  if (v < t.min || v > t.max) throw new CairoPanic(felt("Option::unwrap failed."));
  return v;
}

/** `felt252` into an integer type, `.unwrap()`ed: a signed type reads `P - x` as `-x`. */
export function fromFelt(t: Int, f: bigint): bigint {
  const v = t.min < 0n && f > P / 2n ? f - P : f;
  return narrow(t, v);
}

/** Felt arithmetic, modulo P. */
export const feltAdd = (a: bigint, b: bigint): bigint => (a + b) % P;
export const feltSub = (a: bigint, b: bigint): bigint => (((a - b) % P) + P) % P;
