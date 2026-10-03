// The felt and the integer types of the Cairo code, as the mirror needs them (ADR-0003 *What a
// TypeScript mirror must reproduce*): integers are `bigint` bounded by their Cairo type, a value
// outside it throws where Cairo panics, division truncates, and felt arithmetic is for bitmaps and
// hashes only.

/** The Starknet field's prime, `2^251 + 17 × 2^192 + 1`. */
export const P = 2n ** 251n + 17n * 2n ** 192n + 1n;

/**
 * A Cairo panic: `data` is the panic data as Cairo's short strings (`'window: facing'`,
 * `'Option::unwrap failed.'`), so that a vector's `err` field compares exactly.
 */
export class CairoPanic extends Error {
  readonly data: readonly string[];

  constructor(...data: string[]) {
    super(`Cairo panic: ${data.join(", ")}`);
    this.name = "CairoPanic";
    this.data = data;
  }
}

/** Panics with one short string, as `core::panic_with_felt252` and `assert`. */
export function panic(message: string): never {
  throw new CairoPanic(message);
}

/** An integer type of Cairo: its name and bounds, both inclusive. */
export type IntType = { readonly name: string; readonly min: bigint; readonly max: bigint };

function unsigned(bits: bigint): IntType {
  return { name: `u${bits}`, min: 0n, max: 2n ** bits - 1n };
}

function signed(bits: bigint): IntType {
  return { name: `i${bits}`, min: -(2n ** (bits - 1n)), max: 2n ** (bits - 1n) - 1n };
}

export const u8 = unsigned(8n);
export const u16 = unsigned(16n);
export const u32 = unsigned(32n);
export const u64 = unsigned(64n);
export const u128 = unsigned(128n);
export const i8 = signed(8n);
export const i16 = signed(16n);
export const i32 = signed(32n);

/** `value` as `type`, or the panic of an arithmetic overflow of that type. */
function checked(type: IntType, value: bigint, op: string): bigint {
  if (value < type.min || value > type.max) panic(`${type.name}_${op} Overflow`);
  return value;
}

export function add(type: IntType, a: bigint, b: bigint): bigint {
  return checked(type, a + b, "add");
}

export function sub(type: IntType, a: bigint, b: bigint): bigint {
  return checked(type, a - b, "sub");
}

export function mul(type: IntType, a: bigint, b: bigint): bigint {
  return checked(type, a * b, "mul");
}

/** Cairo's division: truncating toward zero (`bigint` division does), a zero divisor panics. */
export function div(type: IntType, a: bigint, b: bigint): bigint {
  if (b === 0n) panic("Division by 0");
  return checked(type, a / b, "div");
}

/**
 * An argument of a Cairo function typed `type`: Cairo cannot be called outside the type, so a value
 * outside it is a bug of the caller, a `RangeError`, not a Cairo panic.
 */
export function arg(type: IntType, value: bigint): bigint {
  if (value < type.min || value > type.max) throw new RangeError(`${value} is not a ${type.name}`);
  return value;
}

/** An argument typed `felt252`: below `P`, or a `RangeError` (a bug of the caller, as `arg`). */
export function feltArg(value: bigint): bigint {
  if (value < 0n || value >= P) throw new RangeError(`${value} is not a felt`);
  return value;
}

/** `value.try_into().unwrap()` into `type`: the value, or the panic of the failed unwrap. */
export function narrow(type: IntType, value: bigint): bigint {
  if (value < type.min || value > type.max) panic("Option::unwrap failed.");
  return value;
}

/** A felt of a vector or a `Serde`: `value` as `type`, a negative integer read as `P − |v|`. */
export function fromFelt(type: IntType, felt: bigint): bigint {
  if (felt < 0n || felt >= P) throw new RangeError(`not a felt: ${felt}`);
  const value = type.min < 0n && felt > P / 2n ? felt - P : felt;
  if (value < type.min || value > type.max) {
    throw new RangeError(`felt ${felt} is not a ${type.name}`);
  }
  return value;
}

/** An integer of `type` as a felt: a negative integer is `P − |v|`. */
export function toFelt(type: IntType, value: bigint): bigint {
  if (value < type.min || value > type.max) {
    throw new RangeError(`${value} is not a ${type.name}`);
  }
  return value < 0n ? value + P : value;
}

/** A boolean of a `Serde`: 0 or 1, anything else refused. */
export function boolFromFelt(felt: bigint): boolean {
  if (felt !== 0n && felt !== 1n) throw new RangeError(`felt ${felt} is not a bool`);
  return felt === 1n;
}

export function boolToFelt(value: boolean): bigint {
  return value ? 1n : 0n;
}

/** An enum of a `Serde` by its variant's index, below `count`. */
export function variantFromFelt(felt: bigint, count: number): number {
  if (felt < 0n || felt >= BigInt(count)) {
    throw new RangeError(`felt ${felt} is not a variant below ${count}`);
  }
  return Number(felt);
}

/** A Cairo short string (at most 31 ASCII characters) as its felt. */
export function shortString(text: string): bigint {
  if (text.length > 31 || !/^[\x20-\x7e]*$/.test(text)) {
    throw new RangeError(`not a short string: ${text}`);
  }
  let felt = 0n;
  for (const char of text) felt = felt * 256n + BigInt(char.charCodeAt(0));
  return felt;
}

/** A felt as the short string it encodes, or `undefined` when it is not printable ASCII. */
export function readShortString(felt: bigint): string | undefined {
  let text = "";
  for (let rest = felt; rest > 0n; rest /= 256n) {
    const code = Number(rest % 256n);
    if (code < 0x20 || code > 0x7e) return undefined;
    text = String.fromCharCode(code) + text;
  }
  return text;
}
