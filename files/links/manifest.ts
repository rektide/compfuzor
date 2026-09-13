/** LINKS manifest v1/v2 decoding, path binding, and record selection. */

import { lstat, readFile } from "node:fs/promises";
import { dirname, isAbsolute, join, normalize, resolve } from "node:path";

import type { LinksScope as Scope, LinksStrategy as Strategy } from "./cli.ts";

export type LinkPolicy = "preserve" | "fail" | "replace";
export type LinkState = "present" | "absent";
export type LinkStatus = "MANAGED" | "MISSING" | "OVERRIDE" | "CONFLICT" | "SOURCE_MISSING" | "SOURCE_UNUSABLE" | "INVALID";
export interface LinkRecord {
  id: string;
  scope: Scope;
  src: string;
  dest: string;
  policy: LinkPolicy;
  state: LinkState;
  strategies: { available: Strategy[]; default: Strategy };
  compose: boolean;
  runtimeRoots?: ("HOME" | "XDG_RUNTIME_DIR" | "XDG_STATE_HOME")[];
}

export interface Manifest {
  version: 1 | 2;
  deployment?: { dir?: string };
  links: LinkRecord[];
}

export interface ResolvedRecord extends LinkRecord {
  manifest: string;
  srcPath: string;
  destPath: string;
}

export interface LinkRow {
  id: string;
  scope: Scope;
  status: LinkStatus;
  src: string;
  dest: string;
  /** What actually sits at dest: entry kind + readlink target when a symlink. */
  entry?: "symlink" | "file" | "directory" | "special" | "missing";
  target?: string;
  representation?: Strategy;
  action?: string;
  detail?: string;
  manifest?: string;
}

function fail(message: string): never {
  throw new Error(message);
}

function object(value: unknown, description: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${description} must be an object`);
  return value as Record<string, unknown>;
}

function stringField(value: unknown, description: string): string {
  if (typeof value !== "string" || value.length === 0) fail(`${description} must be a non-empty string`);
  return value;
}

function strategiesField(value: unknown, description: string): LinkRecord["strategies"] {
  if (value === undefined) return { available: ["link"], default: "link" };
  const strategies = object(value, description);
  const unknown = Object.keys(strategies).filter((key) => key !== "available" && key !== "default");
  if (unknown.length > 0) fail(`${description} has unknown fields: ${unknown.sort().join(", ")}`);
  if (!Array.isArray(strategies.available) || strategies.available.length === 0) {
    fail(`${description}.available must be a non-empty array`);
  }
  if (strategies.available.some((entry) => entry !== "link" && entry !== "copy")) {
    fail(`${description}.available contains an unsupported strategy`);
  }
  const declared = strategies.available as Strategy[];
  if (new Set(declared).size !== declared.length) fail(`${description}.available contains duplicates`);
  if (strategies.default !== "link" && strategies.default !== "copy") {
    fail(`${description}.default must be link or copy`);
  }
  if (!declared.includes(strategies.default)) fail(`${description}.default must be available`);
  const available = (["link", "copy"] as Strategy[]).filter((strategy) => declared.includes(strategy));
  return { available, default: strategies.default };
}

async function manifestPath(path: string): Promise<string> {
  try {
    if ((await lstat(path)).isDirectory()) return join(path, "links.json");
  } catch {
    // readFile below provides the useful error for absent paths.
  }
  return path;
}

export async function loadManifest(inputPath: string): Promise<{ path: string; manifest: Manifest }> {
  const path = await manifestPath(inputPath);
  let raw: unknown;
  try {
    raw = JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    fail(`cannot read manifest ${path}: ${error instanceof Error ? error.message : String(error)}`);
  }
  const value = object(raw, `manifest ${path}`);
  if (value.version !== 1 && value.version !== 2) fail(`manifest ${path}: unsupported version ${String(value.version)}`);
  const version = value.version;
  if (!Array.isArray(value.links)) fail(`manifest ${path}: links must be an array`);
  const seen = new Set<string>();
  const links = value.links.map((entry, index): LinkRecord => {
    const record = object(entry, `${path}: links[${index}]`);
    const id = stringField(record.id, `${path}: links[${index}].id`);
    if (seen.has(id)) fail(`${path}: duplicate link id ${id}`);
    seen.add(id);
    if (record.scope !== "system" && record.scope !== "user") fail(`${path}: ${id}: invalid scope`);
    if (record.policy !== "preserve" && record.policy !== "fail" && record.policy !== "replace") {
      fail(`${path}: ${id}: invalid policy`);
    }
    if (record.state !== "present" && record.state !== "absent") fail(`${path}: ${id}: invalid state`);
    if (version === 1 && (record.strategies !== undefined || record.compose !== undefined)) {
      fail(`${path}: ${id}: version 1 records cannot declare strategies or compose; rerender as LINKS manifest version 2`);
    }
    let runtimeRoots: LinkRecord["runtimeRoots"];
    if (record.runtimeRoots !== undefined) {
      if (!Array.isArray(record.runtimeRoots) || record.runtimeRoots.some((root) => root !== "HOME" && root !== "XDG_RUNTIME_DIR" && root !== "XDG_STATE_HOME")) {
        fail(`${path}: ${id}: runtimeRoots contains an unsupported root`);
      }
      runtimeRoots = record.runtimeRoots as LinkRecord["runtimeRoots"];
    }
    return {
      id,
      scope: record.scope,
      src: stringField(record.src, `${path}: ${id}: src`),
      dest: stringField(record.dest, `${path}: ${id}: dest`),
      policy: record.policy,
      state: record.state,
      strategies: strategiesField(record.strategies, `${path}: ${id}: strategies`),
      compose: record.compose === undefined
        ? true
        : typeof record.compose === "boolean"
          ? record.compose
          : fail(`${path}: ${id}: compose must be boolean`),
      runtimeRoots,
    };
  });
  let deployment: Manifest["deployment"];
  if (value.deployment !== undefined) {
    const entry = object(value.deployment, `${path}: deployment`);
    if (entry.dir !== undefined) stringField(entry.dir, `${path}: deployment.dir`);
    deployment = { dir: entry.dir as string | undefined };
  }
  return { path, manifest: { version, deployment, links } };
}

function expandPath(value: string, base: string): string {
  let expanded = value;
  const home = process.env.HOME;
  const runtime = process.env.XDG_RUNTIME_DIR;
  const state = process.env.XDG_STATE_HOME || (home ? join(home, ".local/state") : undefined);
  if (value === "~" || value.startsWith("~/")) {
    if (!home) fail(`HOME is required to expand ${value}`);
    expanded = home + value.slice(1);
  } else if (value === "${HOME}" || value.startsWith("${HOME}/")) {
    if (!home) fail(`HOME is required to expand ${value}`);
    expanded = home + value.slice("${HOME}".length);
  } else if (value === "${XDG_RUNTIME_DIR}" || value.startsWith("${XDG_RUNTIME_DIR}/")) {
    if (!runtime) fail(`XDG_RUNTIME_DIR is required to expand ${value}`);
    expanded = runtime + value.slice("${XDG_RUNTIME_DIR}".length);
  } else if (value === "${XDG_STATE_HOME}" || value.startsWith("${XDG_STATE_HOME}/")) {
    if (!state) fail(`HOME or XDG_STATE_HOME is required to expand ${value}`);
    expanded = state + value.slice("${XDG_STATE_HOME}".length);
  } else if (value.startsWith("~") || value.includes("${") || value.includes("$")) {
    fail(`unsupported runtime-root expression: ${value}`);
  }
  return normalize(isAbsolute(expanded) ? expanded : resolve(base, expanded));
}

function idMatches(idPatterns: string[] | undefined, id: string): boolean {
  if (!idPatterns || idPatterns.length === 0) return true;
  return idPatterns.some((pattern) => globMatches(pattern, id));
}

export function resolveRecords(path: string, manifest: Manifest, scope?: Scope, idPatterns?: string[], composed = false): { records: ResolvedRecord[]; invalid: LinkRow[] } {
  const baseValue = manifest.deployment?.dir ?? dirname(resolve(path));
  const base = expandPath(baseValue, dirname(resolve(path)));
  const claims = new Map<string, ResolvedRecord>();
  const records: ResolvedRecord[] = [];
  const invalid: LinkRow[] = [];
  for (const record of manifest.links.filter((entry) => (!scope || entry.scope === scope) && idMatches(idPatterns, entry.id) && (!composed || entry.compose))) {
    try {
      const resolved: ResolvedRecord = {
        ...record,
        manifest: path,
        srcPath: expandPath(record.src, base),
        destPath: expandPath(record.dest, base),
      };
      if (resolved.srcPath === resolved.destPath) fail(`${path}: ${record.id}: source and destination are the same path`);
      const key = `${record.scope}\0${resolved.destPath}`;
      const prior = claims.get(key);
      if (prior && (
        prior.srcPath !== resolved.srcPath
        || prior.policy !== resolved.policy
        || prior.state !== resolved.state
        || prior.compose !== resolved.compose
        || prior.strategies.default !== resolved.strategies.default
        || prior.strategies.available.join("\0") !== resolved.strategies.available.join("\0")
      )) {
        fail(`${path}: conflicting claims for ${resolved.destPath}`);
      }
      claims.set(key, resolved);
      records.push(resolved);
    } catch (error) {
      invalid.push({
        id: record.id,
        scope: record.scope,
        status: "INVALID",
        src: record.src,
        dest: record.dest,
        manifest: path,
        detail: error instanceof Error ? error.message : String(error),
      });
    }
  }
  return { records, invalid };
}

export function globMatches(pattern: string, value: string): boolean {
  let source = "^";
  for (let i = 0; i < pattern.length; i++) {
    const char = pattern[i];
    if (char === "*") source += ".*";
    else if (char === "?") source += ".";
    else source += char.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
  }
  return new RegExp(source + "$").test(value);
}
