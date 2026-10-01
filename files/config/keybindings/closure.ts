/** Captured include closure validation at the existing CONFIG transaction hook. */
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join, normalize } from "node:path";
import { promisify } from "node:util";
import { assertFileGuards, captureFile, type FileGuard } from "../capture.ts";
import { physicalParent, inspectDeliveryEntry } from "../../links/delivery.ts";
import type { Target } from "./model.ts";
import { nativeIncludes, resolveNativeInclude, rewriteNativeIncludes } from "./native.ts";

const exec = promisify(execFile);
export type ClosurePlan = {
  version: 1; target: Target; root: string; captured: Record<string, string>; guards: FileGuard[];
  environment: Record<string, string | undefined>; validator?: string;
};
export type CandidateMap = { version: 1; candidates: { name: string; output: string; candidate: string; link: string | null }[] };
export type FileReader = (path: string, optional: boolean) => Promise<string | undefined>;

export async function entryKey(path: string): Promise<string> { return join(await physicalParent(path), basename(path)); }

/** Reads planned outputs first, including through ordinary symlink aliases. */
export async function plannedReader(planned: Map<string, string>, fallback: FileReader): Promise<FileReader> {
  const physical = new Map<string, string>();
  for (const [path, text] of planned) physical.set(await entryKey(path), text);
  return async (path, optional) => {
    let current = normalize(path);
    const seen = new Set<string>();
    while (!seen.has(current)) {
      seen.add(current);
      const selected = physical.get(await entryKey(current));
      if (selected !== undefined) return selected;
      const entry = await inspectDeliveryEntry(current);
      if (entry.kind !== "symlink") return fallback(path, optional);
      current = entry.targetPath;
    }
    throw new Error(`symlink cycle in native include ${path}`);
  };
}

export async function captureClosure(root: string, target: Target, reader: FileReader, environment: ClosurePlan["environment"]): Promise<Map<string, string>> {
  const captured = new Map<string, string>();
  const active = new Set<string>();
  const visited = new Set<string>();
  const visit = async (path: string, optional: boolean): Promise<void> => {
    path = normalize(path);
    const identity = await entryKey(path);
    if (active.has(identity)) throw new Error(`native include cycle at ${path}`);
    if (visited.has(path)) return;
    visited.add(path);
    const text = await reader(path, optional);
    if (text === undefined) { if (!optional) throw new Error(`missing selected native source ${path}`); return; }
    captured.set(path, text);
    active.add(identity);
    if (active.size > 64) throw new Error("native include closure exceeds 64 levels");
    for (const ref of nativeIncludes(text, target)) await visit(resolveNativeInclude(ref.path, path, target, environment), ref.optional);
    active.delete(identity);
  };
  await visit(root, false);
  return captured;
}

export async function validateClosure(planPath: string, environment: { CONFIG_CANDIDATES_FILE?: string; CONFIG_TRANSACTION?: string }): Promise<void> {
  if (!environment.CONFIG_CANDIDATES_FILE || !environment.CONFIG_TRANSACTION) throw new Error("closure validation requires CONFIG transaction candidate map");
  const plan = JSON.parse(await readFile(planPath, "utf8")) as ClosurePlan;
  const map = JSON.parse(await readFile(environment.CONFIG_CANDIDATES_FILE, "utf8")) as CandidateMap;
  if (plan.version !== 1 || map.version !== 1) throw new Error("unsupported candidate closure version");
  await assertFileGuards(plan.guards);
  const planned = new Map<string, string>();
  for (const candidate of map.candidates) planned.set(candidate.output, await readFile(candidate.candidate, "utf8"));
  if (!planned.has(plan.root)) throw new Error("transaction does not select candidate root");
  const reader = await plannedReader(planned, async (path, optional) => {
    const source = plan.captured[normalize(path)];
    if (source === undefined) { if (optional) return undefined; throw new Error(`uncaptured native source ${path}`); }
    return readFile(source, "utf8");
  });
  const closure = await captureClosure(plan.root, plan.target, reader, plan.environment);
  const layout = join(environment.CONFIG_TRANSACTION, "native-layout");
  const mirrored = (path: string): string => join(layout, normalize(path).slice(1));
  for (const [path, text] of closure) {
    const refs = nativeIncludes(text, plan.target).map((ref) => mirrored(resolveNativeInclude(ref.path, path, plan.target, plan.environment)));
    const copy = mirrored(path);
    await mkdir(dirname(copy), { recursive: true });
    await writeFile(copy, rewriteNativeIncludes(text, plan.target, refs));
  }
  await exec(plan.validator ?? plan.target, plan.target === "niri" ? ["validate", "--config", mirrored(plan.root)] : ["validate", "-c", mirrored(plan.root)]);
  await assertFileGuards(plan.guards);
}

export async function liveFileReader(path: string, optional: boolean): Promise<string | undefined> {
  const file = await captureFile(path);
  if (file.bytes === undefined && !optional) throw new Error(`missing selected native source ${path}`);
  return file.bytes?.toString("utf8");
}
