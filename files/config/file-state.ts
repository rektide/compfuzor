/** Shared regular-file availability and byte comparison observations. */

import { readFile, stat } from "node:fs/promises"

import { inspectDeliveryEntry } from "../links/delivery.ts"

export type ContentComparison = { equal: boolean; error?: string }
export type UsableFile = { usable: boolean; note?: string }

export async function compareFileContents(first: string, second: string): Promise<ContentComparison> {
  try {
    const [one, two] = await Promise.all([readFile(first), readFile(second)])
    return { equal: one.equals(two) }
  } catch (error) {
    return { equal: false, error: `cannot compare ${first} and ${second}: ${error instanceof Error ? error.message : String(error)}` }
  }
}

export async function inspectUsableFile(path: string): Promise<UsableFile> {
  const entry = await inspectDeliveryEntry(path)
  if (entry.kind === "missing") return { usable: false, note: "donor entry missing" }
  if (entry.kind === "directory" || entry.kind === "special") return { usable: false, note: `donor entry is ${entry.kind}` }
  try {
    const followed = await stat(path)
    if (!followed.isFile()) return { usable: false, note: "donor entry does not resolve to a regular file" }
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { usable: false, note: "donor entry is dangling" }
    return { usable: false, note: error instanceof Error ? error.message : String(error) }
  }
  return { usable: true }
}
