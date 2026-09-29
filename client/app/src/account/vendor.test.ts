import ts from "typescript";
import { describe, expect, it } from "vitest";

// ADR-0005 §1: no vendor library outside the module, and no vendor type out of it.
const sources = import.meta.glob<string>(["./*.ts", "!./*.test.ts"], {
  query: "?raw",
  import: "default",
  eager: true,
});
const app = import.meta.glob<string>(["../**/*.{ts,tsx}", "!../account/**", "!../**/*.test.ts"], {
  query: "?raw",
  import: "default",
  eager: true,
});

const IMPORTS_STARKNET = /from\s+["'](starknet|@starknet-io\/[^"']*)["']/;
const VENDOR_FILE = /node_modules\/(starknet|@starknet-io|@noble|@scure)\//;

/** Every declaration of a vendor's library a type reaches, through our own types' members. */
function vendorOrigins(
  checker: ts.TypeChecker,
  type: ts.Type,
  seen = new Set<ts.Type>(),
): string[] {
  if (seen.has(type)) return [];
  seen.add(type);
  const found: string[] = [];
  for (const symbol of [type.getSymbol(), type.aliasSymbol]) {
    for (const declaration of symbol?.getDeclarations() ?? []) {
      const file = declaration.getSourceFile().fileName;
      if (VENDOR_FILE.test(file)) found.push(`${symbol!.getName()} (${file})`);
      if (!file.includes("node_modules")) {
        // Our own type: look at what its members and signatures carry.
        for (const member of type.getProperties()) {
          found.push(
            ...vendorOrigins(checker, checker.getTypeOfSymbolAtLocation(member, declaration), seen),
          );
        }
      }
    }
  }
  for (const signature of type.getCallSignatures()) {
    found.push(...vendorOrigins(checker, signature.getReturnType(), seen));
    for (const parameter of signature.getParameters()) {
      found.push(...vendorOrigins(checker, checker.getTypeOfSymbol(parameter), seen));
    }
  }
  if (type.isUnionOrIntersection()) {
    for (const part of type.types) found.push(...vendorOrigins(checker, part, seen));
  }
  for (const argument of (type as ts.TypeReference).typeArguments ?? []) {
    found.push(...vendorOrigins(checker, argument, seen));
  }
  return found;
}

describe("the vendor stays inside", () => {
  it("only starknet.ts imports the chain library", () => {
    const importers = Object.entries(sources)
      .filter(([, text]) => IMPORTS_STARKNET.test(text))
      .map(([path]) => path);
    expect(importers).toEqual(["./starknet.ts"]);
  });

  it("nothing else in the app imports it but the chain door of NS-1", () => {
    const importers = Object.entries(app)
      .filter(([, text]) => IMPORTS_STARKNET.test(text))
      .map(([path]) => path);
    expect(importers).toEqual(["../chain.ts"]);
  });

  it("no type the module exports reaches a type of the library", () => {
    const index = new URL("./index.ts", import.meta.url).pathname;
    const program = ts.createProgram([index], {
      target: ts.ScriptTarget.ES2023,
      module: ts.ModuleKind.ESNext,
      moduleResolution: ts.ModuleResolutionKind.Bundler,
      strict: true,
      skipLibCheck: true,
      noEmit: true,
    });
    const checker = program.getTypeChecker();
    const module = checker.getSymbolAtLocation(program.getSourceFile(index)!)!;
    const exported = checker.getExportsOfModule(module);
    expect(exported.map((s) => s.getName())).toContain("createStarknetChain");
    const found: string[] = [];
    for (const alias of exported) {
      const symbol = alias.flags & ts.SymbolFlags.Alias ? checker.getAliasedSymbol(alias) : alias;
      const declaration = symbol.getDeclarations()![0]!;
      const type =
        symbol.flags & (ts.SymbolFlags.Interface | ts.SymbolFlags.TypeAlias)
          ? checker.getDeclaredTypeOfSymbol(symbol)
          : checker.getTypeOfSymbolAtLocation(symbol, declaration);
      found.push(...vendorOrigins(checker, type).map((origin) => `${alias.getName()}: ${origin}`));
    }
    expect(found).toEqual([]);
  }, 30_000);
});
