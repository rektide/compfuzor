/** Reusable CONFIG input capture and ordinary pre-commit revision guards. */
import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import { inspectDeliveryEntry } from "../links/delivery.ts";

export type FileGuard = { path: string; kind: "missing" | "file" | "symlink"; hash?: string; target?: string };
export type CapturedFile = { guard: FileGuard; bytes?: Buffer };

export function contentHash(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

export async function captureFile(path: string): Promise<CapturedFile> {
  const entry = await inspectDeliveryEntry(path);
  if (entry.kind === "missing") return { guard: { path, kind: "missing" } };
  if (entry.kind !== "file" && entry.kind !== "symlink") throw new Error(`not a usable configuration file: ${path}`);
  let referent;
  try { referent = await stat(path); } catch (error) {
    if (entry.kind === "symlink" && (error as NodeJS.ErrnoException).code === "ENOENT") return { guard: { path, kind: "symlink", target: entry.target } };
    throw error;
  }
  if (!referent.isFile()) throw new Error(`not a regular configuration referent: ${path}`);
  const bytes = await readFile(path);
  return { bytes, guard: { path, kind: entry.kind, hash: contentHash(bytes), ...(entry.kind === "symlink" ? { target: entry.target } : {}) } };
}

export async function assertFileGuards(guards: readonly FileGuard[]): Promise<void> {
  for (const expected of guards) {
    const current = (await captureFile(expected.path)).guard;
    if (current.kind !== expected.kind || current.hash !== expected.hash || current.target !== expected.target) throw new Error(`configuration source changed since capture: ${expected.path}`);
  }
}
