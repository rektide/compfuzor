/**
 * Fetch one remote of an archive without moving the local base or
 * reconciling the worktree: snapshot, harvest a dirty `@` if recovery does
 * not already cover it, then fetch without abandoning unreachable commits.
 * Untracking is explicit; run `refresh` afterward for reconciliation.
 *
 * Library twin of the CLI `fetch` command: returns structured notices
 * instead of printing. No console I/O happens here.
 */
import { harvest, recoveryCovered, type Notice } from "../recovery/harvest.ts";
import { jj, refs, revision, type ExecutionOptions } from "./jj.ts";
import { snapshot } from "./snapshot.ts";

export type FetchOptions = {
  dest: string;
  label: string;
  remote?: string;
  branch?: string;
  untrack?: "none" | "selected" | "all";
};
export type FetchResult = { remote: string; notices: Notice[] };

export async function fetchRemote(
  options: FetchOptions,
  execution?: ExecutionOptions,
): Promise<FetchResult> {
  const { dest, label } = options;
  const remote = options.remote ?? "origin";
  const untrack = options.untrack ?? "none";
  if (!["none", "selected", "all"].includes(untrack))
    throw new Error(`invalid untrack scope: ${untrack}`);
  if (untrack === "selected" && !options.branch) {
    throw new Error("untrack=selected requires a --branch");
  }
  const notices: Notice[] = [];

  await snapshot(dest, execution);
  const before = await refs(dest, undefined, execution);
  const working = await revision(dest, "@", execution);
  if (!working.empty && !(await recoveryCovered(dest, label, before, working.parents, execution))) {
    notices.push(await harvest(dest, label, "working-copy", working.commit, true, execution));
  }

  // Tracking belongs to the shared repo; only change it when requested.
  for (const ref of before.values()) {
    if (
      ref.remote !== "-" &&
      ref.remote !== "git" &&
      ref.tracked &&
      (untrack === "all" ||
        (untrack === "selected" && ref.remote === remote && ref.name === options.branch))
    ) {
      await jj(
        ["bookmark", "untrack", ref.name, "--remote", ref.remote],
        dest,
        undefined,
        execution,
      );
    }
  }

  // No prune/abandon of unreachable commits: even rewritten upstream history
  // remains reconstructible while we decide which tips need harvest bookmarks.
  await jj(
    [
      "--config",
      "git.abandon-unreachable-commits=false",
      "git",
      "fetch",
      "--remote",
      remote,
      ...(options.branch ? ["--branch", options.branch] : ["--branch", "*", "--tag", "*"]),
    ],
    dest,
    undefined,
    execution,
  );
  return { remote, notices };
}
