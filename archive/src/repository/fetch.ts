/**
 * Fetch one remote of an archive without moving the local base or
 * reconciling the worktree: snapshot, harvest a dirty `@` if recovery does
 * not already cover it, freeze tracked local bookmarks, then fetch with no
 * abandon of unreachable commits. Run `refresh` afterward for reconciliation.
 *
 * Library twin of the CLI `fetch` command: returns structured notices
 * instead of printing. No console I/O happens here.
 */
import { harvest, recoveryCovered, type Notice } from "../recovery/harvest.ts";
import { jj, refs, revision } from "./jj.ts";
import { snapshot } from "./snapshot.ts";

export type FetchOptions = { dest: string; label: string; remote?: string };
export type FetchResult = { remote: string; notices: Notice[] };

export async function fetchRemote(options: FetchOptions): Promise<FetchResult> {
  const { dest, label } = options;
  const remote = options.remote ?? "origin";
  const notices: Notice[] = [];

  await snapshot(dest);
  const before = await refs(dest);
  const working = await revision(dest, "@");
  if (!working.empty && !(await recoveryCovered(dest, label, before, working.parents))) {
    notices.push(await harvest(dest, label, "working-copy", working.commit, true));
  }

  // Freeze *all* tracked local refs before fetching: jj's tracked-remote sync
  // otherwise moves them, and a rewritten upstream can abandon the old tip.
  for (const ref of before.values()) {
    if (ref.remote !== "-" && ref.remote !== "git" && ref.tracked) {
      await jj(["bookmark", "untrack", ref.name, "--remote", ref.remote], dest);
    }
  }

  // No prune/abandon of unreachable commits: even rewritten upstream history
  // remains reconstructible while we decide which tips need harvest bookmarks.
  await jj(
    ["--config", "git.abandon-unreachable-commits=false", "git", "fetch", "--remote", remote],
    dest,
  );
  return { remote, notices };
}
