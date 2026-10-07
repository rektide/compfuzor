/**
 * Transaction-hook adapter for captured native include closures. It reads candidate
 * maps/snapshots and filesystem topology, writes mirrored validation copies only
 * inside CONFIG_TRANSACTION, and runs the native validator. It never changes live
 * outputs or candidate bytes; CONFIG alone owns commit/rollback after hook success.
 * Candidate precedence prevents accidentally validating old live definitions.
 * Observed-state guards bracket validation but do not lock or eliminate races.
 * @see /doc/config/keybinding-consumers.md
 * @see /design/keybindings/implementation1.gpt61sol.md
 */
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join, normalize } from "node:path";
import { promisify } from "node:util";
import { assertFileGuards, captureFile, fileText, type FileGuard } from "../capture.ts";
import { physicalParent, inspectDeliveryEntry } from "../../links/delivery.ts";
import type { Target } from "./model.ts";
import { nativeIncludes, resolveNativeInclude, rewriteNativeIncludes } from "./native.ts";
import { renderRoot } from "./materials.ts";
import { assertRegistryGuards, type RegistryGuard } from "../../../runtime/registry/guard.ts";

const exec = promisify(execFile);
/** Private invocation plan prepared by the consumer, consumed before CONFIG commit. */
export type ClosurePlan = {
  /** Plan schema version; not the ordinary CONFIG spec version. */
  version: 1;
  /** Explicit native validator/format selection. */
  target: Target;
  /** Absolute LIVE root output; its private candidate must be in the transaction map. */
  root: string;
  /** Original normalized absolute paths -> private UTF-8 snapshot files for unselected refs. */
  captured: Record<string, string>;
  /** Input/root/link/parent observations checked before and after validation, not held locks. */
  guards: FileGuard[];
  registryGuards?: RegistryGuard[];
  /** Explicit include expansion values captured by the caller, not ambient env discovery. */
  environment: Record<string, string | undefined>;
  /** Native validator command override; defaults to the target's executable. */
  validator?: string;
  /** Generated canonical outputs needing contextual admission even if edited copies shadow them. */
  definitions?: string[];
};
/** Runner-owned map of all produced candidates, including unchanged live outputs. */
export type CandidateMap = {
  /** Map schema discriminator emitted by config-run.sh. */
  version: 1;
  /** Complete selected recipe inventory available AFTER production/per-recipe validation. */
  candidates: {
    /** CONFIG recipe name, not a stable contribution/block ID. */
    name: string;
    /** Absolute live output entry whose prospective bytes are represented here. */
    output: string;
    /** Private candidate file holding prospective bytes, even for a staged symlink output. */
    candidate: string;
    /** Absolute requested published link target; null means ordinary regular-file delivery. */
    link: string | null;
  }[];
};
/** Read policy for absolute logical native paths; undefined is allowed only for optional refs. */
export type FileReader = (path: string, optional: boolean) => Promise<string | undefined>;

/**
 * Identify a directory entry by resolved physical parent plus its literal basename.
 * Parent aliases are collapsed; the final entry is deliberately NOT followed, so a
 * symlink pending replacement is not confused with its old referent. Existing
 * delivery utilities resolve missing parent suffixes without creating directories.
 * @param path Concrete absolute entry path supplied by selection/closure traversal.
 * @returns Filesystem-aware comparison key, not a content hash or locking token.
 * @throws On filesystem resolution errors from the parent-path helper.
 */
export async function entryKey(path: string): Promise<string> {
  return join(await physicalParent(path), basename(path));
}

/**
 * Build a reader where prospective output text takes precedence over live bytes.
 * It snapshots planned physical-entry keys at construction, then checks those keys
 * BEFORE following each current final symlink. Thus a live alias to a pending
 * regular output returns that candidate, not its old live referent. Fallback gets
 * the originally requested path, preserving that logical file's include base.
 * @param planned Absolute output paths mapped to prepared/candidate text; callers
 * preflight duplicate physical claims and must rebuild this reader after map additions.
 * @param fallback Read policy for paths not claimed by a candidate chain.
 * @returns A topology-reading reader; constructing/calling it writes nothing.
 * @throws On parent/entry I/O errors or a final symlink cycle encountered by the reader.
 */
export async function plannedReader(
  planned: Map<string, string>,
  fallback: FileReader,
): Promise<FileReader> {
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

/**
 * Capture a root and recursively selected includes with an explicit read/env policy.
 * Logical paths retain their own include bases; active physical-entry keys detect
 * recursion, and repeated logical files are visited once. Optional missing refs are
 * absent from the result, never replaced with undisclosed producer/live fallbacks.
 * @param root Absolute logical root path.
 * @param target Native include grammar, not inferred from filename extension.
 * @param reader Candidate/snapshot/live policy chosen explicitly by the caller.
 * @param environment Declared native include variable/HOME values.
 * @returns Original normalized absolute paths and captured text; no layout is written.
 * @throws On missing required refs, cycles, depth beyond 64 active entries, parse,
 * path/environment or reader/filesystem failures.
 */
export async function captureClosure(
  root: string,
  target: Target,
  reader: FileReader,
  environment: ClosurePlan["environment"],
): Promise<Map<string, string>> {
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
    if (text === undefined) {
      if (!optional) throw new Error(`missing selected native source ${path}`);
      return;
    }
    captured.set(path, text);
    active.add(identity);
    if (active.size > 64) throw new Error("native include closure exceeds 64 levels");
    for (const ref of nativeIncludes(text, target))
      await visit(resolveNativeInclude(ref.path, path, target, environment), ref.optional);
    active.delete(identity);
  };
  await visit(root, false);
  return captured;
}

/**
 * Execute CONFIG's read-only-to-live transaction validation hook.
 * The runner calls this after every candidate exists and legacy per-recipe
 * validators have passed, before check/stdout/publication. Candidate bytes override
 * captured unselected files. Only mirrored copies rewrite live include paths to
 * private layout paths, including optional references; live candidates stay unchanged.
 * Effective-root admission is followed, when needed, by a contextual envelope for
 * shadowed generated defaults, never a context-free standalone fragment check.
 * @param planPath Private UTF-8 ClosurePlan JSON written during consumer preparation.
 * @param environment Runner-supplied map path and owned transaction scratch directory.
 * @returns Resolves only when guards and native admission pass; makes no commit claim.
 * @throws On absent/invalid protocol, changed observations, uncaptured/invalid includes,
 * unselected defaults, scratch I/O or native-validator failure. CONFIG handles abort.
 * @see /doc/config/keybinding-consumers.md
 */
export async function validateClosure(
  planPath: string,
  environment: {
    /** Runner-written complete versioned map, available only at the transaction hook. */
    CONFIG_CANDIDATES_FILE?: string;
    /** Runner-owned private directory for mirrored validation files, not live publication. */
    CONFIG_TRANSACTION?: string;
  },
): Promise<void> {
  if (!environment.CONFIG_CANDIDATES_FILE || !environment.CONFIG_TRANSACTION)
    throw new Error("closure validation requires CONFIG transaction candidate map");
  const plan = JSON.parse(await readFile(planPath, "utf8")) as ClosurePlan;
  const map = JSON.parse(
    await readFile(environment.CONFIG_CANDIDATES_FILE, "utf8"),
  ) as CandidateMap;
  if (plan.version !== 1 || map.version !== 1)
    throw new Error("unsupported candidate closure version");
  await assertFileGuards(plan.guards);
  await assertRegistryGuards(plan.registryGuards ?? []);
  const planned = new Map<string, string>();
  for (const candidate of map.candidates)
    planned.set(candidate.output, await readFile(candidate.candidate, "utf8"));
  if (!planned.has(plan.root)) throw new Error("transaction does not select candidate root");
  const fallback: FileReader = async (path, optional) => {
    const source = plan.captured[normalize(path)];
    if (source === undefined) {
      if (optional) return undefined;
      throw new Error(`uncaptured native source ${path}`);
    }
    return readFile(source, "utf8");
  };
  const layout = join(environment.CONFIG_TRANSACTION, "native-layout");
  const mirrored = (path: string): string => join(layout, normalize(path).slice(1));
  const validateRoot = async (root: string): Promise<Map<string, string>> => {
    const closure = await captureClosure(
      root,
      plan.target,
      await plannedReader(planned, fallback),
      plan.environment,
    );
    for (const [path, text] of closure) {
      const refs = nativeIncludes(text, plan.target).map((ref) =>
        mirrored(resolveNativeInclude(ref.path, path, plan.target, plan.environment)),
      );
      const copy = mirrored(path);
      await mkdir(dirname(copy), { recursive: true });
      await writeFile(copy, rewriteNativeIncludes(text, plan.target, refs));
    }
    await exec(
      plan.validator ?? plan.target,
      plan.target === "niri"
        ? ["validate", "--config", mirrored(root)]
        : ["validate", "-c", mirrored(root)],
    );
    return closure;
  };
  const effective = await validateRoot(plan.root);
  const unused = (plan.definitions ?? []).filter((path) => !effective.has(normalize(path)));
  if (unused.length) {
    for (const path of unused)
      if (!planned.has(path)) throw new Error(`unselected generated definition ${path}`);
    // Edited copies legitimately shadow defaults. Still admit every produced
    // canonical definition against the same consumer context, without changing
    // the actual root's references or treating standalone fragments as configs.
    const envelope = join(
      environment.CONFIG_TRANSACTION,
      `definition-admission.${plan.target === "niri" ? "kdl" : "toml"}`,
    );
    planned.set(envelope, renderRoot(plan.target, [], unused, [plan.root]));
    await validateRoot(envelope);
  }
  await assertFileGuards(plan.guards);
  await assertRegistryGuards(plan.registryGuards ?? []);
}

/**
 * Simple explicit live-input read policy for closure callers, without writes.
 * This does not add guards to a plan automatically or override candidate precedence.
 * @param path Concrete native input path to capture/decode as fatal UTF-8.
 * @param optional Whether a missing/dangling input may return undefined.
 * @returns Captured native text, or undefined for an allowed missing input.
 * @throws On required absence, invalid text/non-file referents or capture I/O failure.
 */
export async function liveFileReader(path: string, optional: boolean): Promise<string | undefined> {
  const file = await captureFile(path);
  if (file.bytes === undefined && !optional)
    throw new Error(`missing selected native source ${path}`);
  return fileText(file);
}
