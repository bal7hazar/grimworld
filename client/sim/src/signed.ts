// Signed fields in two's complement: the mirror of `contracts/logic/src/helpers/signed.cairo`
// (`SignedTrait`), an `i8` in 8 bits and an `i16` in 16. A packer adds the bits at the field's
// offset; an unpacker reads them back. Bits are `bigint` (a `u128` of Cairo), values `number`.
// A value outside the type is a bug of the caller (`RangeError`, `arg`); bits too wide for the
// type are the panic of the failed `try_into().unwrap()`, as in Cairo.

import { arg, i8, i16, narrow, u128 } from "./felt";

const P8 = 0x100n;
const P16 = 0x10000n;

/** `SignedTrait::bits8`: the 8 bits of an `i8`, `v` if `v ≥ 0`, else `2^8 + v`. */
export function bits8(value: number): bigint {
  const wide = arg(i8, BigInt(value));
  return wide < 0n ? wide + P8 : wide;
}

/** `SignedTrait::from8`: the `i8` of 8 bits (`bits` below 2^8). */
export function from8(bits: bigint): number {
  const wide = arg(u128, bits);
  return Number(narrow(i8, wide >= 0x80n ? wide - P8 : wide));
}

/** `SignedTrait::bits16`: the 16 bits of an `i16`, `v` if `v ≥ 0`, else `2^16 + v`. */
export function bits16(value: number): bigint {
  const wide = arg(i16, BigInt(value));
  return wide < 0n ? wide + P16 : wide;
}

/** `SignedTrait::from16`: the `i16` of 16 bits (`bits` below 2^16). */
export function from16(bits: bigint): number {
  const wide = arg(u128, bits);
  return Number(narrow(i16, wide >= 0x8000n ? wide - P16 : wide));
}
