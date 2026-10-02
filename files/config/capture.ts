/**
 * Reusable filesystem observation for CONFIG source/root/profile guards. Capture
 * reads entry topology, physical parent and regular referent bytes; it never writes,
 * locks, registers, validates a native schema or commits outputs. UTF-8 decoding
 * is separate so generic registration can capture binary bytes without text coercion.
 * Guard comparisons detect observed changes before/after admission, not atomic
 * snapshots, concurrent-writer isolation or elimination of the check-to-commit race.
 * @see /doc/config/keybinding-consumers.md
 */
import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import { inspectDeliveryEntry, physicalParent } from "../links/delivery.ts";

/** One caller-retained observation, serialized into a private validation plan. */
export type FileGuard = {
  /** Logical concrete file path to reobserve; callers bind portable selectors beforehand. */
  path: string;
  /** Resolved physical parent, detecting directory-symlink retargeting even with equal bytes. */
  parent: string;
  /** Final directory-entry representation, without conflating a symlink and its referent. */
  kind: "missing" | "file" | "symlink";
  /** SHA-256 of captured referent bytes; absent for missing or dangling entries. */
  hash?: string;
  /** Literal stored final symlink target, including relative spelling; absent for other kinds. */
  target?: string;
};
/** Captured raw input plus observation; absence is explicit, never an implicit fallback. */
export type CapturedFile = {
  /** Entry/parent/content observation for later pre-commit comparisons. */
  guard: FileGuard;
  /** Regular referent bytes; undefined for missing or dangling symlink entries. */
  bytes?: Buffer;
};

/**
 * Decode captured bytes strictly as UTF-8, preserving a BOM rather than replacing
 * invalid bytes with different text that native validation would accidentally admit.
 * @param file Existing capture; no additional filesystem observation occurs.
 * @returns Text or undefined when the capture has no usable bytes.
 * @throws On invalid UTF-8, with the logical source path in the diagnostic.
 */
export function fileText(file: CapturedFile): string | undefined {
  if (file.bytes === undefined) return undefined;
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(file.bytes);
  } catch (error) {
    throw new Error(`configuration text is not valid UTF-8: ${file.guard.path}`, { cause: error });
  }
}

/**
 * Compute a deterministic SHA-256 observation without I/O or mutable registration.
 * @param bytes Exact captured referent content, not normalized native text.
 * @returns Hex digest used for equality checks, not an identity/locking guarantee.
 */
export function contentHash(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/**
 * Observe a final file/link entry and read its regular referent without writing.
 * Missing entries and ENOENT-dangling symlinks retain explicit guards but no bytes;
 * caller policy decides whether that absence is optional, seedable or an error.
 * Multiple filesystem reads are not one atomic snapshot; later guards can detect
 * observed changes but cannot prevent them.
 * @param path Concrete invocation-bound file path, normally absolute in CONFIG adapters.
 * @returns Raw bytes when usable plus kind/parent/hash/literal-target observation.
 * @throws On directory/special/nonregular referents or other filesystem errors.
 */
export async function captureFile(path: string): Promise<CapturedFile> {
  const entry = await inspectDeliveryEntry(path);
  const parent = await physicalParent(path);
  if (entry.kind === "missing") return { guard: { path, parent, kind: "missing" } };
  if (entry.kind !== "file" && entry.kind !== "symlink")
    throw new Error(`not a usable configuration file: ${path}`);
  let referent;
  try {
    referent = await stat(path);
  } catch (error) {
    if (entry.kind === "symlink" && (error as NodeJS.ErrnoException).code === "ENOENT")
      return { guard: { path, parent, kind: "symlink", target: entry.target } };
    throw error;
  }
  if (!referent.isFile()) throw new Error(`not a regular configuration referent: ${path}`);
  const bytes = await readFile(path);
  return {
    bytes,
    guard: {
      path,
      parent,
      kind: entry.kind,
      hash: contentHash(bytes),
      ...(entry.kind === "symlink" ? { target: entry.target } : {}),
    },
  };
}

/**
 * Reobserve each guarded input/root and reject changed parent, kind, bytes or target.
 * Closure admission calls this before and after native validation; it supplies no
 * lock, compare-and-swap publication, concurrent-writer isolation or race elimination.
 * @param guards Observations captured by the caller before planning prospective outputs.
 * @returns Resolves when every comparison still matches; does not accept/commit state.
 * @throws On detected changes or capture failure while checking current state.
 */
export async function assertFileGuards(guards: readonly FileGuard[]): Promise<void> {
  for (const expected of guards) {
    const current = (await captureFile(expected.path)).guard;
    if (
      current.parent !== expected.parent ||
      current.kind !== expected.kind ||
      current.hash !== expected.hash ||
      current.target !== expected.target
    )
      throw new Error(`configuration source changed since capture: ${expected.path}`);
  }
}
