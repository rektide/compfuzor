import { randomUUID } from "node:crypto";
import { rename } from "node:fs/promises";
import { join } from "node:path";
import { stamp } from "./harvest.ts";
import { exists, isDirectory, jj } from "./jj.ts";

/** Explicit re-adoption drops jj's broken view, not the Git checkout or backup. */
export async function heal(dest: string, yes: boolean): Promise<string> {
  if (!yes)
    throw new Error(
      "heal is destructive to jj's operation history; pass --yes to back up .jj and re-adopt",
    );
  if (
    !(await isDirectory(dest)) ||
    !(await exists(join(dest, ".git"))) ||
    !(await isDirectory(join(dest, ".jj")))
  )
    throw new Error(`${dest} must be a jj-colocated Git checkout; refusing to re-adopt`);
  const backup = join(dest, `.jj.broken-ghost-${stamp()}-${randomUUID().slice(0, 8)}`);
  await rename(join(dest, ".jj"), backup);
  // If init fails, the backup remains available for manual restore; never delete it.
  await jj(["git", "init", "--colocate"], dest);
  return backup;
}
