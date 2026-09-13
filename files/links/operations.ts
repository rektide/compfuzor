/** LINKS representation assessment and bounded filesystem mutations. */

import { execFile } from "node:child_process";
import { access, constants as fsConstants, lstat, readFile, rm, stat } from "node:fs/promises";
import { dirname } from "node:path";
import { promisify } from "node:util";

import type { LinksStrategy as Strategy, SudoMode } from "./cli.ts";
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
  type LinkRow as Row,
  type ResolvedRecord,
} from "./manifest.ts";

export type LinkApplyOptions = {
  sudoMode: SudoMode;
  strategy?: Strategy;
};

const _execFile = promisify(execFile);

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

async function needsSudo(sudoMode: SudoMode, scope: ResolvedRecord["scope"], destPath: string): Promise<boolean> {
  if (scope === "user") return false;
  if (sudoMode === "always") return true;
  if (sudoMode === "never") return false;
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

export async function sourceState(path: string): Promise<{ entryExists: boolean; regular: boolean }> {
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

export async function classifyRecord(record: ResolvedRecord): Promise<Row> {
  return classifyAssessment(record, await inspectRecord(record));
}


function overwriteSelected(id: string): boolean {
  const setting = process.env.COMPFUZOR_LINK_OVERWRITE?.trim();
  if (!setting) return false;
  if (["1", "true", "y", "yes", "*"].includes(setting.toLowerCase())) return true;
  return setting.split(",").map((part) => part.trim()).filter(Boolean).some((pattern) => globMatches(pattern, id));
}

async function removeManaged(record: ResolvedRecord, action: string, sudoMode: SudoMode): Promise<Row> {
  const sudo = await needsSudo(sudoMode, record.scope, record.destPath);
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

export async function applyRecord(record: ResolvedRecord, options: LinkApplyOptions): Promise<Row> {
  const selectedStrategy = options.strategy;
  if (record.state === "absent") return removeManaged(record, "removed", options.sudoMode);
  const sudo = await needsSudo(options.sudoMode, record.scope, record.destPath);
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

export async function removeRecord(record: ResolvedRecord, sudoMode: SudoMode): Promise<Row> {
  return removeManaged(record, "removed", sudoMode);
}
