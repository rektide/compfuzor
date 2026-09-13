#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON

import { execFile } from "node:child_process";
import { access, constants as fsConstants, lstat, readFile, rm, stat } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  parseLinksArgs,
  resolveSudoMode,
  type LinksCliOptions as Options,
  type LinksScope as Scope,
  type LinksStrategy as Strategy,
  type SudoMode,
} from "./cli.ts";

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
import {
  globMatches,
  loadManifest,
  resolveRecords,
  type LinkRow as Row,
  type LinkStatus as Status,
  type ResolvedRecord,
} from "./manifest.ts";

const DIR = process.env.DIR ?? dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const _execFile = promisify(execFile);

// Privilege routing for mutations (reads never need it). Selected by --sudo
// or COMPFUZOR_LINKS_SUDO:
//   auto (default) -- probe per record whether the dest is writable and
//                     escalate only unwritable ones through sudo
//   always         -- route every mutation through sudo
//   never          -- stay unprivileged; EACCES fails loud
let SUDO_MODE: SudoMode = "auto";

function fail(message: string): never {
  throw new Error(message);
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


type DestinationAssessment = {
  entry: DeliveryEntry;
  kind: "missing" | "healthy" | "foreign" | "directory" | "special";
  sourceEntryExists: boolean;
  sourceRegular: boolean;
  representation?: Strategy;
  healthyRepresentation?: Strategy;
  detail?: string;
};

async function sourceState(path: string): Promise<{ entryExists: boolean; regular: boolean }> {
  let entryExists = false;
  try {
    await lstat(path);
    entryExists = true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  try {
    const source = await stat(path);
    return { entryExists, regular: source.isFile() };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { entryExists, regular: false };
    throw error;
  }
}

async function filesMatch(source: string, destination: string): Promise<boolean> {
  const [sourceBytes, destinationBytes] = await Promise.all([readFile(source), readFile(destination)]);
  return sourceBytes.equals(destinationBytes);
}

async function inspectRecord(record: ResolvedRecord): Promise<DestinationAssessment> {
  const [entry, source] = await Promise.all([inspectDeliveryEntry(record.destPath), sourceState(record.srcPath)]);
  if (entry.kind === "missing") return { entry, kind: "missing", sourceEntryExists: source.entryExists, sourceRegular: source.regular };
  if (entry.kind === "directory") return { entry, kind: "directory", sourceEntryExists: source.entryExists, sourceRegular: source.regular };
  if (entry.kind === "special") return { entry, kind: "special", sourceEntryExists: source.entryExists, sourceRegular: source.regular };
  if (entry.kind === "symlink") {
    const healthy = record.strategies.available.includes("link") && linkMatches(entry, record.srcPath);
    if (healthy) {
      return { entry, kind: "healthy", sourceEntryExists: source.entryExists, sourceRegular: source.regular, representation: "link", healthyRepresentation: "link" };
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
      sourceEntryExists: source.entryExists,
      sourceRegular: source.regular,
      representation: "link",
      detail: dangling ? "dangling link" : "foreign link",
    };
  }
  const healthy = record.strategies.available.includes("copy") && source.regular && await filesMatch(record.srcPath, record.destPath);
  return {
    entry,
    kind: healthy ? "healthy" : "foreign",
    sourceEntryExists: source.entryExists,
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

function classifyAssessment(record: ResolvedRecord, dest: DestinationAssessment, selectedStrategy?: Strategy): Row {
  const common = {
    ...commonRow(record, dest),
  };
  if (record.state === "absent") {
    if (dest.kind === "missing") return { ...common, status: "MANAGED", detail: "absent as requested" };
    if (dest.kind === "healthy") return { ...common, status: "CONFLICT", detail: "should be absent" };
    return { ...common, status: "OVERRIDE" };
  }
  if (!dest.sourceEntryExists) return { ...common, status: "SOURCE_MISSING", detail: "src missing" };
  if (dest.kind === "healthy" && (!selectedStrategy || dest.healthyRepresentation === selectedStrategy)) {
    return { ...common, status: "MANAGED" };
  }
  const operationStrategy = selectedStrategy ?? record.strategies.default;
  if (operationStrategy === "copy" && !dest.sourceRegular) {
    return { ...common, status: "SOURCE_UNUSABLE", detail: "copy source does not resolve to a regular file" };
  }
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
  let row = classifyAssessment(record, dest, selectedStrategy);
  if (row.status === "SOURCE_MISSING" || row.status === "SOURCE_UNUSABLE") return row;
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
  SOURCE_UNUSABLE: "bad-source",
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
  const sourceError = rows.some((row) => row.status === "SOURCE_MISSING" || row.status === "SOURCE_UNUSABLE" || row.status === "INVALID");
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
  const options = parseLinksArgs(process.argv.slice(2), join(DIR, "links.json"));
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
      if (options.strategy === "copy") {
        const sourceStates = await Promise.all(resolved.records.map(async (record) => ({ record, source: await sourceState(record.srcPath) })));
        const unusable = sourceStates.filter(({ record, source }) => record.state === "present" && source.entryExists && !source.regular);
        if (unusable.length > 0) {
          fail(`strategy copy requires a source that resolves to a regular file: ${unusable.map(({ record }) => record.id).join(", ")}`);
        }
      }
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
  if (rows.some((row) => row.status === "SOURCE_MISSING" || row.status === "SOURCE_UNUSABLE" || row.status === "INVALID")) return 2;
  return rows.some((row) => row.status === "MISSING" || row.status === "CONFLICT") ? 1 : 0;
}

main().then(
  (code) => { process.exitCode = code; },
  (error) => {
    console.error(error instanceof Error ? error.stack : String(error));
    process.exitCode = 2;
  },
);
