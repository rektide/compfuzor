/**
 * Pure native include inspection, resolution and text rebinding. Niri is parsed
 * as KDL v1 with source locations; Umbriel is parsed as TOML with large integers
 * preserved. No filesystem/env lookup, subprocess, registration or publication
 * occurs. Callers provide explicit environment and owner paths.
 * Rewriting is for private closure copies or deliberate Niri inline rebinding:
 * Umbriel normalization must not be mistaken for editing unrelated live user TOML.
 * Native validators still own complete compositor-schema admission.
 * @see /doc/config/keybinding-consumers.md
 */
import { getLocation } from "@bgotink/kdl";
import { parse as parseKdl } from "@bgotink/kdl/v1-compat";
import {
  parse as parseToml,
  stringify as stringifyToml,
  TomlDate,
  type TomlTable,
} from "smol-toml";
import { dirname, resolve } from "node:path";
import type { Target } from "./model.ts";
import { kdlString } from "./render.ts";

/** One native reference in parsed order, before owner-relative/environment resolution. */
export type NativeInclude = {
  /** Raw authored string; may be relative, absolute, tilde-rooted or Umbriel env-dependent. */
  path: string;
  /** Native missing-file allowance; required references must never use hidden fallbacks. */
  optional: boolean;
};

function tomlIncludes(table: TomlTable): {
  entries: NativeInclude[];
  rewrite: (paths: string[]) => void;
} {
  const entries: NativeInclude[] = [];
  const arrays: string[][] = [];
  if (table.include !== undefined) {
    if (
      !table.include ||
      typeof table.include !== "object" ||
      Array.isArray(table.include) ||
      table.include instanceof TomlDate
    )
      throw new Error("include must be a table");
    const include = table.include as TomlTable;
    if (
      include.optional !== undefined &&
      (!include.optional ||
        typeof include.optional !== "object" ||
        Array.isArray(include.optional) ||
        include.optional instanceof TomlDate)
    )
      throw new Error("include.optional must be a table");
    for (const [value, optional] of [
      [include.files, false],
      [(include.optional as TomlTable | undefined)?.files, true],
    ] as const) {
      if (value === undefined) continue;
      if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string"))
        throw new Error("include files must be a string array");
      arrays.push(value as string[]);
      entries.push(...(value as string[]).map((path) => ({ path, optional })));
    }
  }
  return {
    entries,
    rewrite(paths) {
      let index = 0;
      for (const array of arrays)
        for (let slot = 0; slot < array.length; slot++) array[slot] = paths[index++];
    },
  };
}

/**
 * Inspect explicit top-level native includes without reading their referenced files.
 * Niri recognizes include nodes; Umbriel returns required files then optional files.
 * Slash-dash/comments/quoted text do not become membership through regex matching.
 * @param text Captured valid-UTF-8 text; capture adapters reject invalid byte sequences.
 * @param target Explicit grammar, independent of filename suffix.
 * @returns Ordered unresolved references, not a full native semantic validation result.
 * @throws On parse errors, invalid include tables/arrays or malformed Niri path arguments.
 */
export function nativeIncludes(text: string, target: Target): NativeInclude[] {
  if (target === "umbriel")
    return tomlIncludes(parseToml(text, { integersAsBigInt: "asNeeded" })).entries;
  return parseKdl(text)
    .nodes.filter((node) => node.getName() === "include")
    .map((node) => {
      const args = node.getArguments();
      if (args.length !== 1 || typeof args[0] !== "string")
        throw new Error("Niri include requires exactly one string path");
      return { path: args[0], optional: node.getProperty("optional") === true };
    });
}

/**
 * Replace reference paths in native text while keeping include order/optional semantics.
 * Niri edits only parsed argument spans in the original bytes-as-text. Umbriel
 * serializes parsed TOML, so comments/formatting may change: use it only on validation
 * copies, never as arbitrary live-root adoption. Niri inline callers use resolved
 * LIVE body-relative paths; validation callers use mirrored PRIVATE paths.
 * @param text Native source/root whose include count determines replacement arity.
 * @param target Target parser/serializer.
 * @param paths One replacement per reference in nativeIncludes order.
 * @returns Rebound text without writing or validating files.
 * @throws On parse errors, wrong replacement arity or unavailable KDL locations.
 */
export function rewriteNativeIncludes(
  text: string,
  target: Target,
  paths: readonly string[],
): string {
  if (target === "umbriel") {
    const table = parseToml(text, { integersAsBigInt: "asNeeded" });
    const inclusion = tomlIncludes(table);
    if (inclusion.entries.length !== paths.length)
      throw new Error("include replacement arity differs");
    inclusion.rewrite([...paths]);
    return stringifyToml(table);
  }
  const doc = parseKdl(text, { storeLocations: true });
  const includes = doc.nodes.filter((node) => node.getName() === "include");
  if (includes.length !== paths.length) throw new Error("include replacement arity differs");
  const edits = includes.map((node, index) => {
    const argument = node.getArgumentEntry(0);
    const location = argument && getLocation(argument.value);
    if (!location) throw new Error("include argument has no source location");
    return {
      start: location.start.offset,
      end: location.end.offset,
      text: kdlString(paths[index]),
    };
  });
  let output = text;
  for (const edit of edits.reverse())
    output = output.slice(0, edit.start) + edit.text + output.slice(edit.end);
  return output;
}

/**
 * Resolve an include against its logical owner's directory and explicit native env.
 * Umbriel expands named $VAR/${VAR}; both adapters support HOME-based tilde paths.
 * No ambient environment is consulted or shell evaluation performed. The owner
 * must be the selected body's location for inline content, not the containing root.
 * @param raw Native authored include string, not a generic CONFIG selector object.
 * @param owner Absolute logical file path determining relative include base.
 * @param target Target-specific variable expansion semantics.
 * @param environment Caller-declared values; missing variables/HOME fail explicitly.
 * @returns Normalized absolute path; does not test existence or select candidates.
 * @throws For absent declared expansions or empty/control-delimited resulting paths.
 */
export function resolveNativeInclude(
  raw: string,
  owner: string,
  target: Target,
  environment: Record<string, string | undefined>,
): string {
  let path = raw;
  if (target === "umbriel")
    path = path.replace(
      /\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)/g,
      (_match, braced: string | undefined, plain: string | undefined) => {
        const key = braced ?? plain!;
        if (!Object.hasOwn(environment, key) || typeof environment[key] !== "string")
          throw new Error(`native include needs explicit environment ${key}`);
        return environment[key]!;
      },
    );
  if (path === "~" || path.startsWith("~/")) {
    if (!environment.HOME) throw new Error("native include needs explicit HOME");
    path = environment.HOME + path.slice(1);
  }
  if (!path || /[\0\t\r\n]/.test(path)) throw new Error(`invalid native include path ${raw}`);
  return resolve(dirname(owner), path);
}
