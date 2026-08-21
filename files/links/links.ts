#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON

import { lstat, mkdir, readFile, readlink, rm, symlink } from "node:fs/promises";
import { dirname, isAbsolute, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

type Command = "apply" | "status" | "audit" | "remove";
type Scope = "system" | "user";
type Policy = "preserve" | "fail" | "replace";
type State = "present" | "absent";
type Format = "human" | "jsonl" | "array";
type Status = "MANAGED" | "MISSING" | "OVERRIDE" | "CONFLICT" | "SOURCE_MISSING" | "INVALID";
interface LinkRecord {
  id: string;
  scope: Scope;
  src: string;
  dest: string;
  policy: Policy;
  state: State;
  runtimeRoots?: ("HOME" | "XDG_RUNTIME_DIR")[];
}

interface Manifest {
  version: 1;
  deployment?: { dir?: string };
  links: LinkRecord[];
}

interface ResolvedRecord extends LinkRecord {
  manifest: string;
  srcPath: string;
  destPath: string;
}

interface Row {
  id: string;
  scope: Scope;
  status: Status;
  src: string;
  dest: string;
  /** What actually sits at dest: entry kind + readlink target when a symlink. */
  entry?: "symlink" | "file" | "directory" | "special" | "missing";
  target?: string;
  action?: string;
  detail?: string;
  manifest?: string;
}

interface Options {
  command: Command;
  scope?: Scope;
  id?: string[];
  format: Format;
  quiet: number;
  paths: string[];
}

const DIR = process.env.DIR ?? dirname(dirname(fileURLToPath(import.meta.url)));
const HELP = `Usage: links <apply|status|audit|remove> [MANIFEST ...] [options]

Manage the version 1 link plan at DIR/links.json. Relative plan paths are
based at deployment.dir (or the manifest directory). No shell expansion is
performed; only leading ~, \${HOME}, and \${XDG_RUNTIME_DIR} are recognized.

Options:
  --scope system|user  Operate on one activation scope
  --id <globs>         Comma-separated glob patterns on record ids
                       (scope:dest); operate on the matching slice only.
                       * and ? match, * crosses / (e.g. '*/.tool-versions').
  --json               Emit one JSON object per row
  --json-array         Emit one JSON array
  -q, -qq              Synopsis only, or no output
  -h, --help           Show this help

audit accepts multiple manifests. A directory argument means its links.json.
Exit: 0 success/in-sync, 1 drift or policy conflict, 2 usage/source error.`;

function fail(message: string): never {
  throw new Error(message);
}

function parseArgs(argv: string[]): Options {
  let command: Command | undefined;
  let scope: Scope | undefined;
  let id: string[] | undefined;
  let format: Format = "human";
  let quiet = 0;
  const paths: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "-h" || arg === "--help") {
      console.log(HELP);
      process.exit(0);
    }
    if (/^-q+$/.test(arg)) {
      quiet += arg.length - 1;
    } else if (arg === "--json") {
      format = "jsonl";
    } else if (arg === "--json-array") {
      format = "array";
    } else if (arg === "--scope") {
      const value = argv[++i];
      if (value !== "system" && value !== "user") fail("--scope must be system or user");
      scope = value;
    } else if (arg === "--id") {
      const value = argv[++i];
      if (!value) fail("--id requires a comma-separated glob list");
      id = (id ?? []).concat(value.split(",").map((part) => part.trim()).filter(Boolean));
    } else if (!command && ["apply", "status", "audit", "remove"].includes(arg)) {
      command = arg as Command;
    } else if (arg.startsWith("-")) {
      fail(`unknown option: ${arg}`);
    } else {
      paths.push(arg);
    }
  }
  if (!command) fail("expected apply, status, audit, or remove");
  if (command !== "audit" && paths.length > 1) fail(`${command} accepts at most one manifest`);
  if (paths.length === 0) paths.push(join(DIR, "links.json"));
  return { command, scope, id, format, quiet, paths };
}

function object(value: unknown, description: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${description} must be an object`);
  return value as Record<string, unknown>;
}

function stringField(value: unknown, description: string): string {
  if (typeof value !== "string" || value.length === 0) fail(`${description} must be a non-empty string`);
  return value;
}

async function manifestPath(path: string): Promise<string> {
  try {
    if ((await lstat(path)).isDirectory()) return join(path, "links.json");
  } catch {
    // readFile below provides the useful error for absent paths.
  }
  return path;
}

async function loadManifest(inputPath: string): Promise<{ path: string; manifest: Manifest }> {
  const path = await manifestPath(inputPath);
  let raw: unknown;
  try {
    raw = JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    fail(`cannot read manifest ${path}: ${error instanceof Error ? error.message : String(error)}`);
  }
  const value = object(raw, `manifest ${path}`);
  if (value.version !== 1) fail(`manifest ${path}: unsupported version ${String(value.version)}`);
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
    let runtimeRoots: LinkRecord["runtimeRoots"];
    if (record.runtimeRoots !== undefined) {
      if (!Array.isArray(record.runtimeRoots) || record.runtimeRoots.some((root) => root !== "HOME" && root !== "XDG_RUNTIME_DIR")) {
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
      runtimeRoots,
    };
  });
  let deployment: Manifest["deployment"];
  if (value.deployment !== undefined) {
    const entry = object(value.deployment, `${path}: deployment`);
    if (entry.dir !== undefined) stringField(entry.dir, `${path}: deployment.dir`);
    deployment = { dir: entry.dir as string | undefined };
  }
  return { path, manifest: { version: 1, deployment, links } };
}

function expandPath(value: string, base: string): string {
  let expanded = value;
  const home = process.env.HOME;
  const runtime = process.env.XDG_RUNTIME_DIR;
  if (value === "~" || value.startsWith("~/")) {
    if (!home) fail(`HOME is required to expand ${value}`);
    expanded = home + value.slice(1);
  } else if (value === "${HOME}" || value.startsWith("${HOME}/")) {
    if (!home) fail(`HOME is required to expand ${value}`);
    expanded = home + value.slice("${HOME}".length);
  } else if (value === "${XDG_RUNTIME_DIR}" || value.startsWith("${XDG_RUNTIME_DIR}/")) {
    if (!runtime) fail(`XDG_RUNTIME_DIR is required to expand ${value}`);
    expanded = runtime + value.slice("${XDG_RUNTIME_DIR}".length);
  } else if (value.startsWith("~") || value.includes("${") || value.includes("$")) {
    fail(`unsupported runtime-root expression: ${value}`);
  }
  return normalize(isAbsolute(expanded) ? expanded : resolve(base, expanded));
}

function idMatches(idPatterns: string[] | undefined, id: string): boolean {
  if (!idPatterns || idPatterns.length === 0) return true;
  return idPatterns.some((pattern) => globMatches(pattern, id));
}

function resolveRecords(path: string, manifest: Manifest, scope?: Scope, idPatterns?: string[]): { records: ResolvedRecord[]; invalid: Row[] } {
  const baseValue = manifest.deployment?.dir ?? dirname(resolve(path));
  const base = expandPath(baseValue, dirname(resolve(path)));
  const claims = new Map<string, ResolvedRecord>();
  const records: ResolvedRecord[] = [];
  const invalid: Row[] = [];
  for (const record of manifest.links.filter((entry) => (!scope || entry.scope === scope) && idMatches(idPatterns, entry.id))) {
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
      if (prior && (prior.srcPath !== resolved.srcPath || prior.policy !== resolved.policy || prior.state !== resolved.state)) {
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

async function exists(path: string): Promise<boolean> {
  try {
    await lstat(path);
    return true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
    throw error;
  }
}

async function destination(record: ResolvedRecord): Promise<{ kind: "missing" | "managed" | "foreign" | "directory" | "other"; target?: string }> {
  let stat;
  try {
    stat = await lstat(record.destPath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { kind: "missing" };
    throw error;
  }
  if (!stat.isSymbolicLink()) {
    if (stat.isDirectory()) return { kind: "directory" };
    return { kind: stat.isFile() ? "foreign" : "other" };
  }
  const target = await readlink(record.destPath);
  const targetPath = normalize(isAbsolute(target) ? target : resolve(dirname(record.destPath), target));
  return { kind: targetPath === record.srcPath ? "managed" : "foreign", target };
}

/** Actual entry kind at dest, from lstat/readlink truth (never the plan). */
function entryOf(dest: Awaited<ReturnType<typeof destination>>): Row["entry"] {
  if (dest.kind === "missing") return "missing";
  if (dest.target !== undefined) return "symlink";
  if (dest.kind === "directory") return "directory";
  return dest.kind === "foreign" ? "file" : "special";
}

/** Actual readlink target, when dest is a symlink. */
function targetOf(dest: Awaited<ReturnType<typeof destination>>): string | undefined {
  return dest.target;
}

async function classify(record: ResolvedRecord): Promise<Row> {
  const dest = await destination(record);
  const common = {
    id: record.id,
    scope: record.scope,
    src: record.srcPath,
    dest: record.destPath,
    manifest: record.manifest,
    entry: entryOf(dest),
    target: targetOf(dest),
  };
  if (record.state === "absent") {
    if (dest.kind === "missing") return { ...common, status: "MANAGED", detail: "absent as requested" };
    if (dest.kind === "managed") return { ...common, status: "CONFLICT", detail: "should be absent" };
    return { ...common, status: "OVERRIDE" };
  }
  if (!(await exists(record.srcPath))) return { ...common, status: "SOURCE_MISSING", detail: "src missing" };
  if (dest.kind === "missing") return { ...common, status: "MISSING" };
  if (dest.kind === "managed") return { ...common, status: "MANAGED" };
  if (record.policy === "preserve") return { ...common, status: "OVERRIDE" };
  return { ...common, status: "CONFLICT", detail: dest.kind === "directory" ? "never replaced" : `${record.policy} policy` };
}

function globMatches(pattern: string, value: string): boolean {
  let source = "^";
  for (let i = 0; i < pattern.length; i++) {
    const char = pattern[i];
    if (char === "*") source += ".*";
    else if (char === "?") source += ".";
    else source += char.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
  }
  return new RegExp(source + "$").test(value);
}

function overwriteSelected(id: string): boolean {
  const setting = process.env.COMPFUZOR_LINK_OVERWRITE?.trim();
  if (!setting) return false;
  if (["1", "true", "y", "yes", "*"].includes(setting.toLowerCase())) return true;
  return setting.split(",").map((part) => part.trim()).filter(Boolean).some((pattern) => globMatches(pattern, id));
}

async function removeManaged(record: ResolvedRecord, action: string): Promise<Row> {
  const dest = await destination(record);
  const common = {
    id: record.id,
    scope: record.scope,
    src: record.srcPath,
    dest: record.destPath,
    manifest: record.manifest,
    entry: entryOf(dest),
    target: targetOf(dest),
  };
  if (dest.kind === "managed") {
    await rm(record.destPath);
    return { ...common, status: "MANAGED", action };
  }
  if (dest.kind === "missing") return { ...common, status: "MANAGED", action: "unchanged", detail: "already absent" };
  return { ...common, status: "OVERRIDE", action: "preserved" };
}

async function apply(record: ResolvedRecord): Promise<Row> {
  if (record.state === "absent") return removeManaged(record, "removed");
  let row = await classify(record);
  if (row.status === "SOURCE_MISSING") return row;
  const dest = await destination(record);
  if (dest.kind === "missing") {
    await mkdir(dirname(record.destPath), { recursive: true });
    await symlink(record.srcPath, record.destPath);
    return { ...row, status: "MANAGED", action: "created", entry: "symlink", target: record.srcPath };
  }
  if (dest.kind === "managed") return { ...row, action: "unchanged" };
  const replace = record.policy === "replace" || (record.policy === "preserve" && overwriteSelected(record.id));
  if (!replace || (dest.kind !== "foreign")) return { ...row, action: "preserved" };
  await rm(record.destPath);
  await symlink(record.srcPath, record.destPath);
  row = { ...row, status: "MANAGED", action: "replaced", entry: "symlink", target: record.srcPath };
  return row;
}

async function removeRecord(record: ResolvedRecord): Promise<Row> {
  return removeManaged(record, "removed");
}

async function audit(paths: string[], scope?: Scope, idPatterns?: string[]): Promise<Row[]> {
  const records: ResolvedRecord[] = [];
  const invalid: Row[] = [];
  for (const input of paths) {
    const loaded = await loadManifest(input);
    const resolved = resolveRecords(loaded.path, loaded.manifest, scope, idPatterns);
    records.push(...resolved.records.filter((record) => record.state === "present"));
    invalid.push(...resolved.invalid);
  }
  const groups = new Map<string, ResolvedRecord[]>();
  for (const record of records) {
    const key = `${record.scope}\0${record.destPath}`;
    groups.set(key, [...(groups.get(key) ?? []), record]);
  }
  return invalid.concat(records.map((record) => {
    const group = groups.get(`${record.scope}\0${record.destPath}`) ?? [];
    const conflict = group.some((other) => other.srcPath !== record.srcPath || other.policy !== record.policy);
    return {
      id: record.id,
      scope: record.scope,
      status: conflict ? "CONFLICT" : "MANAGED",
      src: record.srcPath,
      dest: record.destPath,
      manifest: record.manifest,
      detail: conflict ? `${group.length} incompatible claims` : `${group.length} compatible claim${group.length === 1 ? "" : "s"}`,
    };
  }));
}

/** Plain words for the human table; machine statuses stay unchanged. */
const HUMAN_STATUS: Record<Status, string> = {
  MANAGED: "ok",
  OVERRIDE: "override",
  MISSING: "missing",
  CONFLICT: "conflict",
  SOURCE_MISSING: "no-source",
  INVALID: "invalid",
};

/** One human line: verdict, the link as it stands (dest -> actual), and the
 * wanted side only when the two differ. Mutating verbs replace the verdict
 * (created/replaced/removed read better than ok+action). */
function humanLine(row: Row): string {
  const label = row.action ?? HUMAN_STATUS[row.status] ?? row.status;
  let link = row.dest;
  if (row.entry === "symlink" && row.target !== undefined) link += ` -> ${row.target}`;
  else if (row.entry === "file" || row.entry === "directory" || row.entry === "special") link += ` (${row.entry})`;
  const parts = [label, link];
  if (row.src && row.target !== row.src) {
    const missing = row.status === "SOURCE_MISSING" ? " (missing)" : "";
    parts.push(`wanted ${row.src}${missing}`);
  }
  if (row.detail && row.detail !== "src missing") parts.push(`(${row.detail})`);
  return parts.join("\t");
}

function output(rows: Row[], options: Options): void {
  if (options.quiet >= 2) return;
  const sourceError = rows.some((row) => row.status === "SOURCE_MISSING" || row.status === "INVALID");
  const drift = rows.some((row) => row.status === "MISSING" || row.status === "CONFLICT");
  if (options.quiet === 1) {
    console.log(sourceError ? "ERROR" : drift ? "DRIFT" : "OK");
  } else if (options.format === "jsonl") {
    for (const row of rows) console.log(JSON.stringify(row));
  } else if (options.format === "array") {
    console.log(JSON.stringify(rows, null, 2));
  } else {
    console.log("status\tlink");
    for (const row of rows) console.log(humanLine(row));
  }
}

async function main(): Promise<number> {
  const options = parseArgs(process.argv.slice(2));
  if (["1", "true", "y", "yes"].includes(process.env.COMPFUZOR_LINK_BYPASS?.trim().toLowerCase() ?? "")) return 0;
  let rows: Row[];
  if (options.command === "audit") {
    rows = await audit(options.paths, options.scope, options.id);
  } else {
    const loaded = await loadManifest(options.paths[0]);
    const resolved = resolveRecords(loaded.path, loaded.manifest, options.scope, options.id);
    const operation = options.command === "apply" ? apply : options.command === "remove" ? removeRecord : classify;
    rows = [...resolved.invalid];
    // Mutation is all-or-nothing with respect to plan validity.
    if (resolved.invalid.length === 0 || options.command === "status") {
      for (const record of resolved.records) rows.push(await operation(record));
    }
  }
  output(rows, options);
  if (rows.some((row) => row.status === "SOURCE_MISSING" || row.status === "INVALID")) return 2;
  return rows.some((row) => row.status === "MISSING" || row.status === "CONFLICT") ? 1 : 0;
}

main().then(
  (code) => { process.exitCode = code; },
  (error) => {
    console.error(error instanceof Error ? error.stack : String(error));
    process.exitCode = 2;
  },
);
