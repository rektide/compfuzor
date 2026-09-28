/**
 * Refresh a canonical archive without using Git's worktree-resetting update path.
 *
 * Stdout is one JSON result for Ansible; jj diagnostics and failures go to stderr.
 * Only run this on a checkout whose working tree is not being edited concurrently.
 */

import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { harvest as save, recoveryCovered, type Notice } from "../recovery/harvest.ts";
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
};
export type RefreshResult = { changed: boolean; notices: Notice[] };

export async function refreshArchive(
  options: RefreshOptions,
  execution?: ExecutionOptions,
): Promise<RefreshResult> {
  const { dest, repo, remotes: remotesArg, label, reconcileRemotes } = options;
  const update = options.update ?? "true";
  if (update !== "true" && update !== "false") {
    throw new Error(`argument --update: invalid choice: '${update}' (choose from 'true', 'false')`);
  }
  const urls = declaredRemotes(repo, remotesArg);
  let version = options.version ?? "HEAD";
  let selected = options.remote ?? "origin";
  const marker = version.lastIndexOf("@");
  if (marker !== -1 && urls.has(version.slice(marker + 1))) {
    selected = version.slice(marker + 1);
    version = version.slice(0, marker);
  }
  if (!urls.has(selected)) throw new Error(`selected remote '${selected}' is not declared`);
  if (options.submodules) {
    throw new Error(
      "GIT_SUBMODULES requires explicit submodule safety handling; disable it for this archive render",
    );
  }
  const depth = options.depth === undefined ? undefined : Number(options.depth);
  if (depth !== undefined && (!Number.isInteger(depth) || depth < 1)) {
    throw new Error("GIT_DEPTH must be positive");
  }
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

  // Freeze *all* tracked local refs before fetching: jj's tracked-remote sync
  // otherwise moves them, and a rewritten upstream can abandon the old tip.
  for (const ref of before.values()) {
    if (ref.remote !== "-" && ref.remote !== "git" && ref.tracked) {
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
  for (const name of urls.keys()) {
    await jj(
      ["--config", "git.abandon-unreachable-commits=false", "git", "fetch", "--remote", name],
      dest,
      undefined,
      execution,
    );
  }
  const after = await refs(dest, undefined, execution);
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
  const oldBase = before.get(refKey(base, "-"))?.target ?? null;
  if (oldBase === "conflict") {
    throw new Error(`local bookmark ${base} is conflicted; resolve it before updating`);
  }

  // Restore ownership of the other local branches: they remain local-only,
  // never moved merely because a remote happened to share their name.
  for (const ref of before.values()) {
    if (ref.remote !== "-" || ref.name === base || ref.target === "conflict") continue;
    const current = after.get(refKey(ref.name, "-"));
    if (current === undefined || current.target !== ref.target) {
      await harvest(`${ref.name.replaceAll("/", "-")}-local`, ref.target);
    }
  }

  if (
    oldBase !== null &&
    oldBase !== upstream &&
    !(await ancestor(dest, oldBase, upstream, execution))
  ) {
    await harvest(base.replaceAll("/", "-"), oldBase);
  }
  if (oldBase !== upstream) {
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
  await jj(["bookmark", "track", base, "--remote", selected], dest, undefined, execution);

  // Fetch may have changed the current revision only if external Git refs
  // rewrote it; never assume jj's automatic rebase imported the right state.
  const current = await revision(dest, "@", execution);
  if (
    oldBase === current.commit &&
    oldBase !== upstream &&
    (await ancestor(dest, upstream, current.commit, execution))
  ) {
    // Local @ was itself the ahead base. Keep it as a fixed, bookmarked
    // parent before the next user edit can rewrite that old base tip.
    await jj(["new", "@"], dest, undefined, execution);
    changed = true;
  } else if (!(await ancestor(dest, upstream, current.commit, execution))) {
    if (
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
