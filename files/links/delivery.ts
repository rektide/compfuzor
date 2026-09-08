/** Shared, import-safe filesystem delivery primitives used by LINKS and CONFIGS. */

import { copyFile, lstat, mkdir, readlink, rename, rm, stat, symlink, chmod } from "node:fs/promises"
import { dirname, isAbsolute, join, normalize, resolve } from "node:path"

export type DeliveryEntry =
  | { kind: "missing" }
  | { kind: "file" }
  | { kind: "symlink"; target: string; targetPath: string }
  | { kind: "directory" }
  | { kind: "special" }

export type LinkDeliveryExecutor = {
  mkdir(path: string): Promise<void>
  symlink(source: string, destination: string): Promise<void>
  rename(source: string, destination: string): Promise<void>
  rm(path: string): Promise<void>
}

export const localLinkDeliveryExecutor: LinkDeliveryExecutor = {
  async mkdir(path) { await mkdir(path, { recursive: true }) },
  async symlink(source, destination) { await symlink(source, destination) },
  async rename(source, destination) { await rename(source, destination) },
  async rm(path) { await rm(path, { force: true }) },
}

export async function inspectDeliveryEntry(path: string): Promise<DeliveryEntry> {
  let entry
  try {
    entry = await lstat(path)
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { kind: "missing" }
    throw error
  }
  if (entry.isSymbolicLink()) {
    const target = await readlink(path)
    const targetPath = normalize(isAbsolute(target) ? target : resolve(dirname(path), target))
    return { kind: "symlink", target, targetPath }
  }
  if (entry.isFile()) return { kind: "file" }
  if (entry.isDirectory()) return { kind: "directory" }
  return { kind: "special" }
}

export function linkMatches(entry: DeliveryEntry, source: string): boolean {
  return entry.kind === "symlink" && entry.targetPath === normalize(resolve(source))
}

function temporaryPath(destination: string): string {
  return join(dirname(destination), `.${destination.split("/").pop()}.delivery-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`)
}

function assertReplaceable(entry: DeliveryEntry, destination: string): void {
  if (entry.kind === "directory" || entry.kind === "special") {
    throw new Error(`delivery destination is not a regular file or symlink: ${destination}`)
  }
}

function assertDistinct(source: string, destination: string): void {
  if (normalize(resolve(source)) === normalize(resolve(destination))) {
    throw new Error(`delivery source and destination are the same path: ${source}`)
  }
}

export async function replaceWithLink(
  source: string,
  destination: string,
  executor: LinkDeliveryExecutor = localLinkDeliveryExecutor,
): Promise<void> {
  assertDistinct(source, destination)
  assertReplaceable(await inspectDeliveryEntry(destination), destination)
  await executor.mkdir(dirname(destination))
  const temporary = temporaryPath(destination)
  try {
    await executor.symlink(source, temporary)
    await executor.rename(temporary, destination)
  } catch (error) {
    await executor.rm(temporary).catch(() => undefined)
    throw error
  }
}

export async function replaceWithCopy(source: string, destination: string): Promise<void> {
  assertDistinct(source, destination)
  const sourceStat = await stat(source)
  if (!sourceStat.isFile()) throw new Error(`delivery source is not a regular file: ${source}`)
  assertReplaceable(await inspectDeliveryEntry(destination), destination)
  await mkdir(dirname(destination), { recursive: true })
  const temporary = temporaryPath(destination)
  try {
    await copyFile(source, temporary)
    await chmod(temporary, sourceStat.mode & 0o777)
    await rename(temporary, destination)
  } catch (error) {
    await rm(temporary, { force: true }).catch(() => undefined)
    throw error
  }
}
