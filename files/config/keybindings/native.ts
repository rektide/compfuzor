/** Pure native include inspection; only validation copies are normalized. */
import { getLocation } from "@bgotink/kdl";
import { parse as parseKdl } from "@bgotink/kdl/v1-compat";
import { parse as parseToml, stringify as stringifyToml, TomlDate, type TomlTable } from "smol-toml";
import { dirname, resolve } from "node:path";
import type { Target } from "./model.ts";
import { kdlString } from "./render.ts";

export type NativeInclude = { path: string; optional: boolean };

/** Knuffel accepts an omitted node terminator immediately before `}`; strict
 * KDL v1 parsers do not. Insert only that punctuation OUTSIDE strings/comments,
 * with an offset map so include edits still preserve the original live bytes. */
function niriParseText(text: string): { text: string; offsets: number[] } {
  let output = "";
  const offsets: number[] = [];
  let separated = true;
  const append = (start: number, end: number): void => {
    for (let index = start; index < end; index++) { offsets.push(index); output += text[index]; }
  };
  for (let index = 0; index < text.length;) {
    if (text.startsWith("//", index)) {
      const end = text.indexOf("\n", index);
      append(index, end === -1 ? text.length : end);
      index = end === -1 ? text.length : end;
      continue;
    }
    if (text.startsWith("/*", index)) {
      let end = index + 2, depth = 1;
      while (end < text.length && depth) {
        if (text.startsWith("/*", end)) { depth++; end += 2; }
        else if (text.startsWith("*/", end)) { depth--; end += 2; }
        else end++;
      }
      append(index, end); index = end; continue;
    }
    const raw = /^r(#+)?"/.exec(text.slice(index));
    if (raw) {
      const close = '"' + (raw[1] ?? "");
      const found = text.indexOf(close, index + raw[0].length);
      const end = found === -1 ? text.length : found + close.length;
      append(index, end); index = end; separated = false; continue;
    }
    if (text[index] === '"') {
      let end = index + 1;
      while (end < text.length) { if (text[end] === "\\") end += 2; else if (text[end++] === '"') break; }
      append(index, Math.min(end, text.length)); index = end; separated = false; continue;
    }
    const character = text[index];
    if (character === "}" && !separated) { offsets.push(index); output += ";"; }
    append(index, index + 1);
    if (character === ";" || character === "\n" || character === "\r" || character === "{") separated = true;
    else if (!/\s/.test(character)) separated = false;
    index++;
  }
  offsets.push(text.length);
  return { text: output, offsets };
}

function tomlIncludes(table: TomlTable): { entries: NativeInclude[]; rewrite: (paths: string[]) => void } {
  const entries: NativeInclude[] = [];
  const arrays: string[][] = [];
  if (table.include !== undefined) {
    if (!table.include || typeof table.include !== "object" || Array.isArray(table.include) || table.include instanceof TomlDate) throw new Error("include must be a table");
    const include = table.include as TomlTable;
    if (include.optional !== undefined && (!include.optional || typeof include.optional !== "object" || Array.isArray(include.optional) || include.optional instanceof TomlDate)) throw new Error("include.optional must be a table");
    for (const [value, optional] of [[include.files, false], [(include.optional as TomlTable | undefined)?.files, true]] as const) {
      if (value === undefined) continue;
      if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string")) throw new Error("include files must be a string array");
      arrays.push(value as string[]);
      entries.push(...(value as string[]).map((path) => ({ path, optional })));
    }
  }
  return { entries, rewrite(paths) { let index = 0; for (const array of arrays) for (let slot = 0; slot < array.length; slot++) array[slot] = paths[index++]; } };
}

export function nativeIncludes(text: string, target: Target): NativeInclude[] {
  if (target === "umbriel") return tomlIncludes(parseToml(text)).entries;
  return parseKdl(niriParseText(text).text).nodes.filter((node) => node.getName() === "include").map((node) => {
    const args = node.getArguments();
    if (args.length !== 1 || typeof args[0] !== "string") throw new Error("Niri include requires exactly one string path");
    return { path: args[0], optional: node.getProperty("optional") === true };
  });
}

export function rewriteNativeIncludes(text: string, target: Target, paths: readonly string[]): string {
  if (target === "umbriel") {
    const table = parseToml(text);
    const inclusion = tomlIncludes(table);
    if (inclusion.entries.length !== paths.length) throw new Error("include replacement arity differs");
    inclusion.rewrite([...paths]);
    return stringifyToml(table);
  }
  const normalized = niriParseText(text);
  const doc = parseKdl(normalized.text, { storeLocations: true });
  const includes = doc.nodes.filter((node) => node.getName() === "include");
  if (includes.length !== paths.length) throw new Error("include replacement arity differs");
  const edits = includes.map((node, index) => {
    const argument = node.getArgumentEntry(0);
    const location = argument && getLocation(argument.value);
    if (!location) throw new Error("include argument has no source location");
    return { start: normalized.offsets[location.start.offset], end: normalized.offsets[location.end.offset], text: kdlString(paths[index]) };
  });
  let output = text;
  for (const edit of edits.reverse()) output = output.slice(0, edit.start) + edit.text + output.slice(edit.end);
  return output;
}

export function resolveNativeInclude(raw: string, owner: string, target: Target, environment: Record<string, string | undefined>): string {
  let path = raw;
  if (target === "umbriel") path = path.replace(/\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)/g, (_match, braced: string | undefined, plain: string | undefined) => {
    const key = braced ?? plain!;
    if (environment[key] === undefined) throw new Error(`native include needs explicit environment ${key}`);
    return environment[key]!;
  });
  if (path === "~" || path.startsWith("~/")) {
    if (!environment.HOME) throw new Error("native include needs explicit HOME");
    path = environment.HOME + path.slice(1);
  }
  if (!path || /[\0\t\r\n]/.test(path)) throw new Error(`invalid native include path ${raw}`);
  return resolve(dirname(owner), path);
}
