/** Pure native include inspection; only validation copies are normalized. */
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

export type NativeInclude = { path: string; optional: boolean };

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
