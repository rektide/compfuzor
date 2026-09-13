#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON

import { execFile } from "node:child_process";
import { access, constants as fsConstants, lstat, readFile, rm, stat } from "node:fs/promises";
import { dirname, isAbsolute, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  inspectDeliveryEntry,
  linkMatches,
  localCopyDeliveryExecutor,
  localLinkDeliveryExecutor,
  replaceWithCopy,
  replaceWithLink,
  type CopyDeliveryExecutor,
  type DeliveryEntry,
  type LinkDeliveryExecutor,
} from "./delivery.ts";

type Command = "apply" | "status" | "audit" | "remove";
type Scope = "system" | "user";
type Policy = "preserve" | "fail" | "replace";
type State = "present" | "absent";
type Strategy = "link" | "copy";
type Format = "human" | "jsonl" | "array";
type Status = "MANAGED" | "MISSING" | "OVERRIDE" | "CONFLICT" | "SOURCE_MISSING" | "INVALID";
interface LinkRecord {
  id: string;
  scope: Scope;
  src: string;
  dest: string;
  policy: Policy;
  state: State;
  strategies: { available: Strategy[]; default: Strategy };
  compose: boolean;
  runtimeRoots?: ("HOME" | "XDG_RUNTIME_DIR" | "XDG_STATE_HOME")[];
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
  representation?: Strategy;
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
  sudo?: string;
  strategy?: Strategy;
  composed: boolean;
}

const DIR = process.env.DIR ?? dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const _execFile = promisify(execFile);

type SudoMode = "never" | "auto" | "always";

// Privilege routing for mutations (reads never need it). Selected by --sudo
// or COMPFUZOR_LINKS_SUDO:
//   auto (default) -- probe per record whether the dest is writable and
//                     escalate only unwritable ones through sudo
//   always         -- route every mutation through sudo
//   never          -- stay unprivileged; EACCES fails loud
let SUDO_MODE: SudoMode = "auto";

function _sudoWord(value: string): SudoMode | undefined {
  const raw = value.trim().toLowerCase();
  if (raw === "auto") return "auto";
  if (["always", "1", "true", "y", "yes"].includes(raw)) return "always";
  if (["never", "0", "false", "n", "no"].includes(raw)) return "never";
  return undefined;
}

function resolveSudoMode(flagValue: string | undefined): SudoMode {
  if (flagValue !== undefined) {
    const mode = _sudoWord(flagValue);
    if (!mode) fail(`--sudo expects auto, always, or never (got ${flagValue})`);
    return mode;
  }
  const envValue = process.env.COMPFUZOR_LINKS_SUDO;
  if (envValue === undefined || envValue.trim() === "") return "auto";
  const mode = _sudoWord(envValue);
  if (!mode) fail(`COMPFUZOR_LINKS_SUDO must be auto, always, or never (got ${envValue})`);
  return mode;
}

async function destWritable(destPath: string): Promise<boolean> {
  let dir = dirname(destPath);
  for (;;) {
    try {
      await access(dir, fsConstants.W_OK | fsConstants.X_OK);
      return true;
    } catch (error) {
      // walk up to the nearest existing ancestor: that is the directory
      // mkdir -p would have to create (and remove/replace) under
      if ((error as NodeJS.ErrnoException).code === "ENOENT" && dirname(dir) !== dir) {
        dir = dirname(dir);
        continue;
      }
      return false;
    }
  }
}

async function needsSudo(scope: Scope, destPath: string): Promise<boolean> {
  if (scope === "user") return false;
  if (SUDO_MODE === "always") return true;
  if (SUDO_MODE === "never") return false;
  return !(await destWritable(destPath));
}

function linkExecutor(sudo: boolean): LinkDeliveryExecutor {
  if (!sudo) return localLinkDeliveryExecutor;
  return {
    async mkdir(path) { await _execFile("sudo", ["mkdir", "-p", "--", path]); },
    async symlink(source, destination) { await _execFile("sudo", ["ln", "-s", "--", source, destination]); },
    async rename(source, destination) { await _execFile("sudo", ["mv", "-T", "--", source, destination]); },
    async rm(path) { await _execFile("sudo", ["rm", "-f", "--", path]); },
  };
}

function copyExecutor(sudo: boolean): CopyDeliveryExecutor {
  if (!sudo) return localCopyDeliveryExecutor;
  return {
    async mkdir(path) { await _execFile("sudo", ["mkdir", "-p", "--", path]); },
    async copyFile(source, destination) { await _execFile("sudo", ["cp", "--", source, destination]); },
    async chmod(path, mode) { await _execFile("sudo", ["chmod", mode.toString(8), "--", path]); },
    async rename(source, destination) { await _execFile("sudo", ["mv", "-T", "--", source, destination]); },
    async rm(path) { await _execFile("sudo", ["rm", "-f", "--", path]); },
  };
}

async function rmLink(path: string, sudo: boolean): Promise<void> {
  if (sudo) await _execFile("sudo", ["rm", "-f", "--", path]);
  else await rm(path);
}

const HELP = `Usage: links <apply|status|audit|remove> [MANIFEST ...] [options]

Manage the version 1 link plan at DIR/links.json. Relative plan paths are
based at deployment.dir (or the manifest directory). No shell expansion is
performed; only leading ~, \${HOME}, \${XDG_RUNTIME_DIR}, and
\${XDG_STATE_HOME} are recognized. XDG_STATE_HOME defaults to
\${HOME}/.local/state per the XDG base-directory specification.

Options:
  --scope system|user  Operate on one activation scope
  --id <globs>         Comma-separated glob patterns on record ids
                       (scope:dest); operate on the matching slice only.
                        * and ? match, * crosses / (e.g. '*/.tool-versions').
  --strategy link|copy Apply using this representation. A healthy alternate
                        declared representation is replaced. No fallback when
                        the selected records do not offer the strategy.
  --composed           Apply only records participating in generic install
                        composition. Direct apply without it includes all.
  --json               Emit one JSON object per row
  --json-array         Emit one JSON array
  --sudo [auto|always|never]
                       Mutation privilege routing: auto (the default) probes
                       each dest and escalates only unwritable records through
                       sudo; always routes all mutations through sudo; never
                       stays unprivileged. Bare --sudo means always. Overrides
                       COMPFUZOR_LINKS_SUDO.
  -q, -qq              Synopsis only, or no output
  -h, --help           Show this help

audit accepts multiple manifests. A directory argument means its links.json.
Environment:
  COMPFUZOR_LINKS_SUDO  auto (default) | always | 1/true/yes | never | 0/false/no
                        Same routing as --sudo, when the flag is absent.
  COMPFUZOR_LINK_BYPASS     1/true/y/yes exits 0 without doing anything.
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
  let sudo: string | undefined;
  let strategy: Strategy | undefined;
  let composed = false;
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
    } else if (arg === "--sudo") {
      const next = argv[i + 1];
      if (next !== undefined && _sudoWord(next) !== undefined) {
        sudo = next;
        i++;
      } else {
        sudo = "always";
      }
    } else if (arg === "--id") {
      const value = argv[++i];
      if (!value) fail("--id requires a comma-separated glob list");
      id = (id ?? []).concat(value.split(",").map((part) => part.trim()).filter(Boolean));
    } else if (arg === "--strategy") {
      const value = argv[++i];
      if (value !== "link" && value !== "copy") fail("--strategy must be link or copy");
      strategy = value;
    } else if (arg === "--composed") {
      composed = true;
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
  if (strategy !== undefined && command !== "apply") fail("--strategy is only valid with apply");
  if (composed && command !== "apply") fail("--composed is only valid with apply");
  if (paths.length === 0) paths.push(join(DIR, "links.json"));
  return { command, scope, id, format, quiet, paths, sudo, strategy, composed };
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
  return { path, manifest: { version: 1, deployment, links } };
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

function resolveRecords(path: string, manifest: Manifest, scope?: Scope, idPatterns?: string[], composed = false): { records: ResolvedRecord[]; invalid: Row[] } {
  const baseValue = manifest.deployment?.dir ?? dirname(resolve(path));
  const base = expandPath(baseValue, dirname(resolve(path)));
  const claims = new Map<string, ResolvedRecord>();
  const records: ResolvedRecord[] = [];
  const invalid: Row[] = [];
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

type DestinationAssessment = {
  entry: DeliveryEntry;
  kind: "missing" | "healthy" | "foreign" | "directory" | "special";
  sourceAvailable: boolean;
  sourceRegular: boolean;
  representation?: Strategy;
  healthyRepresentation?: Strategy;
  detail?: string;
};

async function sourceState(path: string): Promise<{ available: boolean; regular: boolean }> {
  try {
    const source = await stat(path);
    return { available: true, regular: source.isFile() };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { available: false, regular: false };
    throw error;
  }
}

async function filesMatch(source: string, destination: string): Promise<boolean> {
  const [sourceBytes, destinationBytes] = await Promise.all([readFile(source), readFile(destination)]);
  return sourceBytes.equals(destinationBytes);
}

async function inspectRecord(record: ResolvedRecord): Promise<DestinationAssessment> {
  const [entry, source] = await Promise.all([inspectDeliveryEntry(record.destPath), sourceState(record.srcPath)]);
  if (entry.kind === "missing") return { entry, kind: "missing", sourceAvailable: source.available, sourceRegular: source.regular };
  if (entry.kind === "directory") return { entry, kind: "directory", sourceAvailable: source.available, sourceRegular: source.regular };
  if (entry.kind === "special") return { entry, kind: "special", sourceAvailable: source.available, sourceRegular: source.regular };
  if (entry.kind === "symlink") {
    const healthy = record.strategies.available.includes("link") && linkMatches(entry, record.srcPath);
    if (healthy) {
      return { entry, kind: "healthy", sourceAvailable: source.available, sourceRegular: source.regular, representation: "link", healthyRepresentation: "link" };
    }
    let dangling = false;
    try {
      await stat(record.destPath);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") dangling = true;
      else throw error;
    }
    return {
      entry,
      kind: "foreign",
      sourceAvailable: source.available,
      sourceRegular: source.regular,
      representation: "link",
      detail: dangling ? "dangling link" : "foreign link",
    };
  }
  const healthy = record.strategies.available.includes("copy") && source.regular && await filesMatch(record.srcPath, record.destPath);
  return {
    entry,
    kind: healthy ? "healthy" : "foreign",
    sourceAvailable: source.available,
    sourceRegular: source.regular,
    representation: "copy",
    healthyRepresentation: healthy ? "copy" : undefined,
    detail: record.strategies.available.includes("copy") ? "copy bytes differ" : undefined,
  };
}

function entryOf(assessment: DestinationAssessment): Row["entry"] {
  return assessment.entry.kind;
}

function commonRow(record: ResolvedRecord, assessment: DestinationAssessment) {
  return {
    id: record.id,
    scope: record.scope,
    src: record.state === "absent" ? "" : record.srcPath,
    dest: record.destPath,
    manifest: record.manifest,
    entry: entryOf(assessment),
    target: assessment.entry.kind === "symlink" ? assessment.entry.target : undefined,
    representation: assessment.representation,
  };
}

function classifyAssessment(record: ResolvedRecord, dest: DestinationAssessment): Row {
  const common = {
    ...commonRow(record, dest),
  };
  if (record.state === "absent") {
    if (dest.kind === "missing") return { ...common, status: "MANAGED", detail: "absent as requested" };
    if (dest.kind === "healthy") return { ...common, status: "CONFLICT", detail: "should be absent" };
    return { ...common, status: "OVERRIDE" };
  }
  if (!dest.sourceAvailable) return { ...common, status: "SOURCE_MISSING", detail: "src missing" };
  if (dest.kind === "missing") return { ...common, status: "MISSING" };
  if (dest.kind === "healthy") return { ...common, status: "MANAGED" };
  if (record.policy === "preserve") return { ...common, status: "OVERRIDE" };
  const detail = dest.kind === "directory" || dest.kind === "special"
    ? "never replaced"
    : dest.detail
      ? `${dest.detail}; ${record.policy} policy`
      : `${record.policy} policy`;
  return { ...common, status: "CONFLICT", detail };
}

async function classify(record: ResolvedRecord): Promise<Row> {
  return classifyAssessment(record, await inspectRecord(record));
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
  const sudo = await needsSudo(record.scope, record.destPath);
  const dest = await inspectRecord(record);
  const common = commonRow(record, dest);
  if (dest.kind === "healthy") {
    await rmLink(record.destPath, sudo);
    return { ...common, status: "MANAGED", action, detail: sudo ? "via sudo" : undefined };
  }
  if (dest.kind === "missing") return { ...common, status: "MANAGED", action: "unchanged", detail: "already absent" };
  return { ...common, status: "OVERRIDE", action: "preserved" };
}

async function deliver(record: ResolvedRecord, strategy: Strategy, sudo: boolean): Promise<void> {
  if (strategy === "link") await replaceWithLink(record.srcPath, record.destPath, linkExecutor(sudo));
  else await replaceWithCopy(record.srcPath, record.destPath, copyExecutor(sudo));
}

async function apply(record: ResolvedRecord, selectedStrategy?: Strategy): Promise<Row> {
  if (record.state === "absent") return removeManaged(record, "removed");
  const sudo = await needsSudo(record.scope, record.destPath);
  const dest = await inspectRecord(record);
  let row = classifyAssessment(record, dest);
  if (row.status === "SOURCE_MISSING") return row;
  const strategy = selectedStrategy ?? record.strategies.default;
  if (dest.kind === "missing") {
    await deliver(record, strategy, sudo);
    return { ...row, status: "MANAGED", action: "created", entry: strategy === "link" ? "symlink" : "file", target: strategy === "link" ? record.srcPath : undefined, representation: strategy, detail: sudo ? "via sudo" : undefined };
  }
  if (dest.kind === "healthy" && (!selectedStrategy || dest.healthyRepresentation === selectedStrategy)) return { ...row, action: "unchanged" };
  if (dest.kind === "healthy") {
    await deliver(record, strategy, sudo);
    return { ...row, status: "MANAGED", action: "switched", entry: strategy === "link" ? "symlink" : "file", target: strategy === "link" ? record.srcPath : undefined, representation: strategy, detail: sudo ? "via sudo" : undefined };
  }
  const replace = record.policy === "replace" || (record.policy === "preserve" && overwriteSelected(record.id));
  if (!replace || dest.kind !== "foreign") return { ...row, action: "preserved" };
  await deliver(record, strategy, sudo);
  row = { ...row, status: "MANAGED", action: "replaced", entry: strategy === "link" ? "symlink" : "file", target: strategy === "link" ? record.srcPath : undefined, representation: strategy, detail: sudo ? "via sudo" : undefined };
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
    const conflict = group.some((other) => (
      other.srcPath !== record.srcPath
      || other.policy !== record.policy
      || other.compose !== record.compose
      || other.strategies.default !== record.strategies.default
      || other.strategies.available.join("\0") !== record.strategies.available.join("\0")
    ));
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

/** Verdict column: mutating verbs (created/replaced/removed) read better
 * than ok+action, so the verb replaces the status word for those rows. */
function humanLineLabel(row: Row): string {
  return row.action ?? HUMAN_STATUS[row.status] ?? row.status;
}

/** src column: the plan's src (what the link should point at). */
function srcCell(row: Row): string {
  return row.src ?? "";
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
    // apply/remove: only changed or problem rows are worth reporting; a
    // satisfied manifest prints nothing at all (the bin wrapper's "complete"
    // is the feedback). status/audit keep the full table.
    const visible = options.command === "apply" || options.command === "remove"
      ? rows.filter((row) => row.action !== "unchanged")
      : rows;
    if (visible.length === 0) return;
    console.log("status\tdest\tsrc\tactual\tnote");
    for (const row of visible) {
      const note = row.detail ? `(${row.detail})` : "";
      const actual = row.entry === "symlink" && row.target !== undefined
        ? row.target
        : row.entry === "file" || row.entry === "directory" || row.entry === "special"
          ? `(${row.entry})`
          : "";
      console.log([humanLineLabel(row), row.dest, srcCell(row), actual, note].map((cell) => (cell === "" ? "\"\"" : cell)).join("\t"));
    }
  }
}

async function main(): Promise<number> {
  const options = parseArgs(process.argv.slice(2));
  SUDO_MODE = resolveSudoMode(options.sudo);
  if (["1", "true", "y", "yes"].includes(process.env.COMPFUZOR_LINK_BYPASS?.trim().toLowerCase() ?? "")) return 0;
  let rows: Row[];
  if (options.command === "audit") {
    rows = await audit(options.paths, options.scope, options.id);
  } else {
    const loaded = await loadManifest(options.paths[0]);
      const resolved = resolveRecords(loaded.path, loaded.manifest, options.scope, options.id, options.composed);
    if ((options.command === "apply" || options.command === "remove") && SUDO_MODE === "always" && resolved.records.some((record) => record.scope === "user")) {
      fail("--sudo always is not permitted for user-scope link mutations");
    }
    if (options.command === "apply" && options.strategy) {
      const unavailable = resolved.records.filter((record) => record.state === "present" && !record.strategies.available.includes(options.strategy!));
      if (unavailable.length > 0) fail(`strategy ${options.strategy} is unavailable for: ${unavailable.map((record) => record.id).join(", ")}`);
    }
    const operation = options.command === "apply"
      ? (record: ResolvedRecord) => apply(record, options.strategy)
      : options.command === "remove"
        ? removeRecord
        : classify;
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
