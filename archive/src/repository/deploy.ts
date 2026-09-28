/**
 * A Compfuzor deployment is a real jj workspace (and Git worktree) of the
 * canonical archive. Never convert, replace, or clear an occupied destination.
 */
import { lstat, mkdir, readFile, readdir, realpath, stat } from "node:fs/promises";
import { createHash } from "node:crypto";
import { basename, dirname, join, relative, resolve } from "node:path";
import { safeLabel } from "../recovery/harvest.ts";
import { refKey, refs, jj, type ExecutionOptions } from "./jj.ts";
import { declaredRemotes, mismatchError, remoteDiff } from "./remotes.ts";
import { refreshArchive, type RefreshOptions, type RefreshResult } from "./refresh.ts";

export type DeployOptions = Omit<RefreshOptions, "dest"> & { archive: string; workspace: string };

const entry = async (path: string) => {
  try {
    return await lstat(path);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
};

/** Like {@link entry}, but follows a symlinked final component. */
const followEntry = async (path: string) => {
  try {
    return await stat(path);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
};

/**
 * An archive reached through a symlink is the archive it points at: relocated
 * `~/archive/<org>/<repo>` entries are legitimate shared repositories. A
 * dangling link falls back to the link itself so it is reported as an
 * unprepared path rather than treated as a clone candidate.
 */
const archiveEntryAt = async (archive: string) => {
  const declared = await entry(archive);
  return declared?.isSymbolicLink() ? ((await followEntry(archive)) ?? declared) : declared;
};

/** Canonicalize an absent destination via its nearest existing ancestor. */
const canonicalPath = async (path: string): Promise<string> =>
  (await entry(path)) ? realpath(path) : join(await canonicalPath(dirname(path)), basename(path));

const within = (parent: string, child: string): boolean => {
  const path = relative(parent, child);
  return path === "" || (path !== ".." && !path.startsWith("../") && !path.startsWith("..\\"));
};

const gitWorktreeBelongsTo = async (archive: string, workspace: string): Promise<boolean> => {
  const gitLink = await entry(`${workspace}/.git`);
  if (!gitLink?.isFile()) return false;
  const pointer = (await readFile(`${workspace}/.git`, "utf8")).trim();
  return (
    pointer.startsWith("gitdir: ") &&
    (await realpath(resolve(workspace, pointer.slice(8)))).startsWith(
      `${await realpath(`${archive}/.git`)}/worktrees/`,
    )
  );
};

export async function deployWorkspace(
  options: DeployOptions,
  execution?: ExecutionOptions,
): Promise<RefreshResult> {
  const archive = resolve(options.archive);
  const workspace = resolve(options.workspace);
  const archiveEntry = await archiveEntryAt(archive);
  if (
    archiveEntry &&
    (!archiveEntry.isDirectory() ||
      !(await entry(`${archive}/.jj`))?.isDirectory() ||
      !(await entry(`${archive}/.git`))?.isDirectory())
  ) {
    throw new Error(`${archive} is not a jj-colocated archive; prepare it separately`);
  }
  const workspaceEntry = await entry(workspace);
  if (workspaceEntry && !workspaceEntry.isDirectory()) {
    throw new Error(
      `${workspace} is occupied; move it aside or clean it up manually before creating a jj workspace`,
    );
  }
  const actualArchive = await canonicalPath(archive);
  const actualWorkspace = await canonicalPath(workspace);
  if (within(actualArchive, actualWorkspace) || within(actualWorkspace, actualArchive)) {
    throw new Error(
      `archive ${archive} and workspace ${workspace} must be distinct, non-nested paths`,
    );
  }
  const contents = workspaceEntry ? await readdir(workspace) : [];
  const existing = contents.length > 0;
  let addGitWorktree = false;
  if (existing) {
    // Admit an existing child jj workspace of this archive even if it has no
    // Git worktree yet. Never treat an unrelated jj repo or a partial/broken
    // .git entry as a candidate for progressive colocation.
    if (!archiveEntry || !(await entry(`${workspace}/.jj`))?.isDirectory()) {
      throw new Error(
        `${workspace} is occupied; move it aside or clean it up manually before creating a jj workspace`,
      );
    }
    const gitEntry = await entry(`${workspace}/.git`);
    const jjPointer = await entry(`${workspace}/.jj/repo`);
    if (
      !jjPointer?.isFile() ||
      (await realpath(
        resolve(`${workspace}/.jj`, (await readFile(`${workspace}/.jj/repo`, "utf8")).trim()),
      )) !== (await realpath(`${archive}/.jj/repo`)) ||
      (await jj(["workspace", "root"], workspace, { readOnly: true }, execution)) !== workspace ||
      (gitEntry !== undefined && !(await gitWorktreeBelongsTo(archive, workspace)))
    ) {
      throw new Error(
        `${workspace} is not a verified jj workspace of ${archive}; refusing to change it`,
      );
    }
    addGitWorktree = gitEntry === undefined;
  }

  let createdArchive: RefreshResult = { changed: false, notices: [] };
  if (!archiveEntry) {
    // The workspace admission check happens before any clone or fetch.
    createdArchive = await refreshArchive({ ...options, dest: archive }, execution);
  } else if (!options.reconcileRemotes) {
    const differences = await remoteDiff(
      archive,
      declaredRemotes(options.repo, options.remotes),
      execution,
      true,
    );
    if (differences.some((difference) => difference.actual !== null)) {
      throw mismatchError(archive, differences, options.repo, options.remotes);
    }
  }
  if (addGitWorktree) {
    await jj(["git", "colocation", "enable"], workspace, undefined, execution);
    if (!(await gitWorktreeBelongsTo(archive, workspace))) {
      throw new Error(`jj did not create a Git worktree of ${archive} at ${workspace}`);
    }
  }
  if (!existing) {
    const urls = declaredRemotes(options.repo, options.remotes);
    let remote = options.remote ?? "origin";
    let branch = options.version ?? "HEAD";
    const at = branch.lastIndexOf("@");
    if (at !== -1 && urls.has(branch.slice(at + 1))) {
      remote = branch.slice(at + 1);
      branch = branch.slice(0, at);
    }
    if (!urls.has(remote)) throw new Error(`selected remote '${remote}' is not declared`);
    const available = await refs(archive, { readOnly: true }, execution);
    if (branch === "HEAD") {
      branch = ["main", "master"].find((name) => available.has(refKey(name, remote))) ?? "";
    }
    if (!branch || !available.has(refKey(branch, remote))) {
      throw new Error(
        `${branch || "HEAD"}@${remote} is unavailable in ${archive}; fetch it before creating ${workspace}`,
      );
    }
    if (available.get(refKey(branch, remote))?.target === "conflict") {
      throw new Error(`${branch}@${remote} is conflicted; resolve it before creating ${workspace}`);
    }
    await mkdir(dirname(workspace), { recursive: true });
    const workspaceName = `compfuzor-${safeLabel(options.label)}-${createHash("sha256").update(workspace).digest("hex").slice(0, 12)}`;
    await jj(
      [
        "workspace",
        "add",
        "--colocate",
        "--name",
        workspaceName,
        "--revision",
        `${branch}@${remote}`,
        workspace,
      ],
      archive,
      undefined,
      execution,
    );
  }
  const result = await refreshArchive({ ...options, dest: workspace }, execution);
  return {
    changed: createdArchive.changed || !existing || addGitWorktree || result.changed,
    notices: [
      ...createdArchive.notices,
      ...(!existing
        ? [
            {
              kind: "notice" as const,
              message: `created jj workspace ${workspace} backed by ${archive}`,
            },
          ]
        : []),
      ...(addGitWorktree
        ? [{ kind: "notice" as const, message: `added Git worktree to jj workspace ${workspace}` }]
        : []),
      ...result.notices,
    ],
  };
}
