/**
 * Refresh a canonical archive without using Git's worktree-resetting update path.
 *
 * Stdout is one JSON result for Ansible; jj diagnostics and failures go to stderr.
 * Only run this on a checkout whose working tree is not being edited concurrently.
 */

import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import {
  harvest as save,
  recoveryCovered,
  saveDisplacedTip,
  type Notice,
} from "../recovery/harvest.ts";
import {
  ancestor,
  exists,
  isDirectory,
  jj,
  refKey,
  refs,
  revision,
  type BookmarkRef,
  type ExecutionOptions,
} from "./jj.ts";
import { declaredRemotes, mismatchError, reconcile, remoteDiff } from "./remotes.ts";
import { snapshot } from "./snapshot.ts";

export type RefreshOptions = {
  dest: string;
  repo: string;
  remotes: string;
  label: string;
  remote?: string;
  version?: string;
  depth?: string;
  submodules?: boolean;
  update?: string;
  reconcileRemotes?: boolean;
  fetchScope?: "all" | "selected";
  untrack?: "none" | "selected" | "all";
  saveDisplaced?: boolean;
};
export type RefreshResult = { changed: boolean; notices: Notice[] };

/** Pure option checks shared with deployment before any destination mutation. */
export function validateRefreshOptions(
  options: Pick<RefreshOptions, "update" | "fetchScope" | "untrack" | "submodules" | "depth">,
): void {
  const update = options.update ?? "true";
  if (update !== "true" && update !== "false") {
    throw new Error(`argument --update: invalid choice: '${update}' (choose from 'true', 'false')`);
  }
  const fetchScope: string = options.fetchScope ?? "all";
  const untrack: string = options.untrack ?? "none";
  if (fetchScope !== "all" && fetchScope !== "selected")
    throw new Error(`invalid fetch scope: ${fetchScope}`);
  if (!["none", "selected", "all"].includes(untrack))
    throw new Error(`invalid untrack scope: ${untrack}`);
  if (options.submodules) {
    throw new Error(
      "GIT_SUBMODULES requires explicit submodule safety handling; disable it for this archive render",
    );
  }
  const depth = options.depth === undefined ? undefined : Number(options.depth);
  if (depth !== undefined && (!Number.isInteger(depth) || depth < 1)) {
    throw new Error("GIT_DEPTH must be positive");
  }
}

export async function refreshArchive(
  options: RefreshOptions,
  execution?: ExecutionOptions,
): Promise<RefreshResult> {
  const { dest, repo, remotes: remotesArg, label, reconcileRemotes } = options;
  validateRefreshOptions(options);
  const update = options.update ?? "true";
  const fetchScope: string = options.fetchScope ?? "all";
  const untrack: string = options.untrack ?? "none";
  const urls = declaredRemotes(repo, remotesArg);
  let version = options.version ?? "HEAD";
  let selected = options.remote ?? "origin";
  let followSelectedRemote = selected !== "origin";
  const marker = version.lastIndexOf("@");
  if (marker !== -1 && urls.has(version.slice(marker + 1))) {
    selected = version.slice(marker + 1);
    version = version.slice(0, marker);
    followSelectedRemote = true;
  }
  if (!urls.has(selected)) throw new Error(`selected remote '${selected}' is not declared`);
  const depth = options.depth === undefined ? undefined : Number(options.depth);
  const notices: Notice[] = [];
  let changed = false;
  let cloned = false;
  const harvest = async (kind: string, target: string, copy = false): Promise<void> => {
    notices.push(await save(dest, label, kind, target, copy, execution));
    changed = true;
  };

  if (!(await exists(dest))) {
    await mkdir(dirname(dest), { recursive: true });
    const command = ["git", "clone", "--colocate", "--remote", selected];
    if (depth !== undefined) command.push("--depth", String(depth));
    if (version !== "HEAD") command.push("--branch", version);
    await jj([...command, urls.get(selected) as string, dest], dirname(dest), undefined, execution);
    notices.push({ kind: "notice", message: `cloned jj-colocated archive ${dest}` });
    changed = true;
    cloned = true;
  } else if (!(await isDirectory(dest)) || !(await exists(join(dest, ".git")))) {
    throw new Error(`${dest} exists but is not a colocated Git checkout; refusing to replace it`);
  } else if (!(await exists(join(dest, ".jj")))) {
    await jj(["git", "init", "--git-repo", join(dest, ".git"), dest], dest, undefined, execution);
    notices.push({ kind: "notice", message: `adopted existing Git archive into jj: ${dest}` });
    changed = true;
  }

  await snapshot(dest, execution);
  const before = await refs(dest, undefined, execution);
  const selectedBranch =
    version !== "HEAD"
      ? version
      : ((["main", "master"] as const).find((name) => before.has(refKey(name, selected))) ?? null);
  const working = await revision(dest, "@", execution);
  const work = working.commit;
  const empty = working.empty;
  const parents = working.parents;

  const differences = await remoteDiff(dest, urls, execution);
  if (differences.some((difference) => difference.actual !== null) && !reconcileRemotes) {
    throw mismatchError(dest, differences, repo, remotesArg);
  }
  if (differences.length) {
    await reconcile(dest, differences, execution);
    changed = true;
  }

  if (update === "false" && before.size > 0) {
    return { changed, notices };
  }

  // HEAD is the conventional base. Explicit versions select branch bookmarks.
  // For an initial clone, fetch is still necessary for extra remotes/branches.
  // A dirty @ is already a jj commit. Do not mint repeated recovery names
  // for the same revision on consecutive renders without an upstream change.
  if (!empty && !(await recoveryCovered(dest, label, before, parents, execution))) {
    await harvest("working-copy", work, true);
  }

  // Untracking is an explicit escape hatch, never the default protection
  // policy: tracking belongs to the shared repo, not this workspace.
  for (const ref of before.values()) {
    if (
      ref.remote !== "-" &&
      ref.remote !== "git" &&
      ref.tracked &&
      (untrack === "all" ||
        (untrack === "selected" && ref.remote === selected && ref.name === selectedBranch))
    ) {
      await jj(
        ["bookmark", "untrack", ref.name, "--remote", ref.remote],
        dest,
        undefined,
        execution,
      );
      changed = true;
    }
  }

  // A branch-limited fetch is available for a narrow operator run; the
  // default imports all declared remotes, retaining normal jj tracking.
  for (const name of fetchScope === "all" ? urls.keys() : [selected]) {
    await jj(
      [
        "--config",
        "git.abandon-unreachable-commits=false",
        "git",
        "fetch",
        "--remote",
        name,
        ...(fetchScope === "all"
          ? ["--branch", "*", "--tag", "*"]
          : selectedBranch !== null
            ? ["--branch", selectedBranch]
            : []),
      ],
      dest,
      undefined,
      execution,
    );
  }
  const after = await refs(dest, undefined, execution);
  // Fetching an unrelated branch is still a repository change even when the
  // selected deployment branch has not moved.
  for (const [key, ref] of after) {
    if (
      ref.remote !== "-" &&
      ref.remote !== "git" &&
      (before.get(key)?.target !== ref.target || before.get(key)?.tracked !== ref.tracked)
    ) {
      changed = true;
    }
  }
  for (const [key, ref] of before) {
    if (ref.remote !== "-" && ref.remote !== "git" && !after.has(key)) changed = true;
  }
  const base =
    version !== "HEAD"
      ? version
      : ((["main", "master"] as const).find((name) => after.has(refKey(name, selected))) ?? null);
  if (base === null || !after.has(refKey(base, selected))) {
    throw new Error(
      `remote ${selected} does not have branch ${version}; specify GIT_VERSION explicitly`,
    );
  }
  const upstream = (after.get(refKey(base, selected)) as BookmarkRef).target;
  if (upstream === "conflict") {
    throw new Error(`remote ${base}@${selected} is conflicted`);
  }
  let selectedSaved = false;
  // A tracked bookmark that diverged from its remote can become conflicted
  // during fetch. Compare exact pre/post targets, not the ambiguous bookmark
  // name. Resolve only conflicts caused by this fetch; preexisting conflicts
  // and branches tracked on multiple remotes need an operator decision.
  for (const ref of before.values()) {
    if (
      ref.remote === "-" ||
      ref.remote === "git" ||
      !ref.tracked ||
      (fetchScope === "selected" && (ref.remote !== selected || ref.name !== base))
    )
      continue;
    const oldLocal = before.get(refKey(ref.name, "-"))?.target;
    const newRemote = after.get(refKey(ref.name, ref.remote))?.target;
    if (
      !oldLocal ||
      oldLocal === "conflict" ||
      !newRemote ||
      newRemote === "conflict" ||
      ref.target === "conflict" ||
      newRemote === ref.target ||
      oldLocal === ref.target
    )
      continue;
    if (
      (await ancestor(dest, oldLocal, newRemote, execution)) ||
      (await ancestor(dest, newRemote, oldLocal, execution))
    )
      continue;
    const tracked = [...before.values()].filter(
      (other) =>
        other.name === ref.name && other.remote !== "-" && other.remote !== "git" && other.tracked,
    );
    if (tracked.length !== 1) {
      notices.push({
        kind: "notice",
        message: `${ref.name}: multiple tracked remotes diverged; resolve manually`,
      });
      continue;
    }
    if (options.saveDisplaced === false) {
      notices.push({
        kind: "notice",
        message: `${ref.name}: local and ${ref.remote} diverged; bookmark left conflicted`,
      });
      continue;
    }
    notices.push(await saveDisplacedTip(dest, ref.name, oldLocal, execution));
    await jj(["bookmark", "set", "-B", "-r", newRemote, ref.name], dest, undefined, execution);
    if (ref.name === base && ref.remote === selected) selectedSaved = true;
    changed = true;
  }
  const reconciled = await refs(dest, undefined, execution);
  const oldBase = before.get(refKey(base, "-"))?.target ?? null;
  if (oldBase === "conflict") {
    throw new Error(`local bookmark ${base} is conflicted; resolve it before updating`);
  }

  const currentBase = reconciled.get(refKey(base, "-"))?.target;
  if (currentBase === "conflict") {
    throw new Error(`${base} is conflicted after fetch; resolve it before updating this workspace`);
  }
  // A local-ahead bookmark stays ahead; a normal tracked fast-forward has
  // already moved itself. Only create/move the selected base if it is behind.
  if (
    currentBase === undefined ||
    (currentBase !== upstream && !(await ancestor(dest, upstream, currentBase, execution)))
  ) {
    if (
      oldBase !== null &&
      currentBase !== undefined &&
      currentBase !== upstream &&
      options.saveDisplaced === false &&
      !(await ancestor(dest, currentBase, upstream, execution))
    ) {
      throw new Error(
        `${base} has local work not covered by ${base}@${selected}; save or resolve it before updating`,
      );
    }
    await jj(["bookmark", "set", "-B", "-r", upstream, base], dest, undefined, execution);
    if (oldBase === null) {
      notices.push({ kind: "bookmark-created", name: base, target: upstream });
    } else {
      notices.push({ kind: "notice", message: `${base} -> ${upstream} (${selected})` });
    }
    changed = true;
  } else if (cloned) {
    notices.push({ kind: "bookmark-created", name: base, target: upstream });
  }
  if (untrack === "none" && !reconciled.get(refKey(base, selected))?.tracked) {
    await jj(["bookmark", "track", base, "--remote", selected], dest, undefined, execution);
  }

  // Fetch may have changed the current revision only if external Git refs
  // rewrote it; never assume jj's automatic rebase imported the right state.
  const current = await revision(dest, "@", execution);
  if (followSelectedRemote && current.empty && current.parents.join(",") !== upstream) {
    // Explicit branch@remote selects the checkout's base even when a local
    // bookmark follows another remote ahead of it. Preserve dirty @ first
    // (above); do not rewind the shared local bookmark to select a workspace.
    await jj(["new", upstream], dest, undefined, execution);
    changed = true;
    notices.push({ kind: "notice", message: `advanced checkout to ${base}@${selected}` });
  } else if (
    oldBase === current.commit &&
    oldBase !== upstream &&
    (await ancestor(dest, upstream, current.commit, execution))
  ) {
    // Local @ was itself the ahead base. Keep it as a fixed, bookmarked
    // parent before the next user edit can rewrite that old base tip.
    await jj(["new", "@"], dest, undefined, execution);
    changed = true;
  } else if (!(await ancestor(dest, upstream, current.commit, execution))) {
    if (selectedSaved) {
      await jj(["new", upstream], dest, undefined, execution);
      changed = true;
      notices.push({
        kind: "notice",
        message: `advanced deployment checkout to ${base}@${selected}; local tip saved`,
      });
    } else if (
      current.empty &&
      oldBase !== null &&
      current.parents.join(",") === oldBase &&
      (await ancestor(dest, oldBase, upstream, execution))
    ) {
      await jj(["rebase", "-r", "@", "-d", base], dest, undefined, execution);
    } else {
      // Never rewrite a bookmarked dirty @: jj moves bookmarks with a
      // rewritten change. A merge keeps the exact pre-fetch worktree as
      // its first parent, and exposes any conflicts for the operator.
      if (empty && current.commit !== work) {
        await harvest("head", work);
      }
      await jj(["new", "@", base], dest, undefined, execution);
    }
    changed = true;
    notices.push({ kind: "notice", message: `merged local checkout with ${base}@${selected}` });
  }
  if ((await revision(dest, "@", execution)).conflict) {
    notices.push({
      kind: "notice",
      message: "working copy has merge conflicts; resolve them before building",
    });
  }
  if ((before.get(refKey(base, selected))?.target ?? null) !== upstream) {
    changed = true;
  }
  return { changed, notices };
}
