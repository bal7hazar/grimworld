/**
 * The funding key, held so that it cannot be printed by accident: every way a value is turned into
 * text (a template, `JSON.stringify`, `console.log`, `util.inspect`) shows `[secret]`. Only
 * `reveal()` gives the value, and only the chain module calls it, to build its signer.
 */
const HIDDEN = "[secret]";

export class Secret {
  readonly #value: string;

  constructor(value: string) {
    this.#value = value;
  }

  reveal(): string {
    return this.#value;
  }

  /**
   * The ways the value could be written as text, for the logger to remove from any line: as given,
   * without its prefix, as a 64-digit hex, as a decimal, lower and upper case.
   */
  forms(): string[] {
    const forms = new Set<string>([this.#value]);
    try {
      const value = BigInt(this.#value);
      const hex = value.toString(16);
      for (const form of [hex, hex.padStart(64, "0"), value.toString(10)]) {
        forms.add(form);
        forms.add(form.toUpperCase());
      }
    } catch {
      // not a number: only the value as given
    }
    // The shortest forms first would cut a longer one in two: the longest are removed first.
    return [...forms].filter((form) => form.length >= 8).sort((a, b) => b.length - a.length);
  }

  toString(): string {
    return HIDDEN;
  }

  toJSON(): string {
    return HIDDEN;
  }

  [Symbol.for("nodejs.util.inspect.custom")](): string {
    return HIDDEN;
  }
}
