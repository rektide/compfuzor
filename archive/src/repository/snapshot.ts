/**
 * Snapshot an archive worktree: materialize visible heads, then import
 * colocated Git refs and snapshot tracked/untracked working-copy changes.
 *
 * Library twin of the CLI `snapshot` command: returns a structured result
 * instead of printing. The conflicted-bookmark list comes from the health
 * preflight that must precede any history walk.
 */
import { preflight } from "./health.ts";
import { jj, type ExecutionOptions } from "./jj.ts";

export type SnapshotResult = { dest: string; conflicts: string[] };

export async function snapshot(
  dest: string,
  execution?: ExecutionOptions,
): Promise<SnapshotResult> {
  const conflicts = await preflight(dest, {}, execution);
  // This snapshots tracked/untracked changes and imports local Git branches.
  // Do not continue to fetch if jj cannot snapshot the worktree.
  await jj(["status"], dest, undefined, execution);
  return { dest, conflicts };
}
