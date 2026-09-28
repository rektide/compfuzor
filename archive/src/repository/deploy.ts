/**
 * A Compfuzor deployment is a real jj workspace (and Git worktree) of the
 * canonical archive. Never convert, replace, or clear an occupied destination.
 */
import { lstat, mkdir, readFile, readdir, realpath } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { refKey, refs, jj, type ExecutionOptions } from "./jj.ts";
import { declaredRemotes } from "./remotes.ts";
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

export async function deployWorkspace(
  options: DeployOptions,
  execution?: ExecutionOptions,
): Promise<RefreshResult> {
  const archive = resolve(options.archive);
  const workspace = resolve(options.workspace);
  const relativePath = relative(archive, workspace);
  if (relativePath === "" || (!relativePath.startsWith("..") && relativePath !== "..")) {
    throw new Error(`workspace ${workspace} must be outside archive ${archive}`);
  }

  const archiveEntry = await entry(archive);
  if (archiveEntry && (!archiveEntry.isDirectory() || !(await entry(`${archive}/.jj`)) || !(await entry(`${archive}/.git`)))) {
    throw new Error(`${archive} is not a jj-colocated archive; prepare it separately`);
  }
  const workspaceEntry = await entry(workspace);
  if (workspaceEntry && !workspaceEntry.isDirectory()) {
    throw new Error(`${workspace} is occupied; move it aside or clean it up manually before creating a jj workspace`);
  }
  const contents = workspaceEntry ? await readdir(workspace) : [];
  const existing = contents.length > 0;
  if (existing) {
    // Validate both jj's shared store and the colocated Git worktree. A
    // checkout belonging to some other archive must never be refreshed here.
    if (!archiveEntry || !(await entry(`${workspace}/.jj`)) || !(await entry(`${workspace}/.git`))) {
      throw new Error(`${workspace} is occupied; move it aside or clean it up manually before creating a jj workspace`);
    }
    const gitEntry = await entry(`${workspace}/.git`);
    const jjPointer = await entry(`${workspace}/.jj/repo`);
    const gitPointer = gitEntry?.isFile() ? (await readFile(`${workspace}/.git`, "utf8")).trim() : "";
    if (!gitEntry?.isFile() || !jjPointer?.isFile() || !gitPointer.startsWith("gitdir: ") ||
        !(await realpath(resolve(workspace, gitPointer.slice(8)))).startsWith(`${await realpath(`${archive}/.git`)}/worktrees/`) ||
        (await realpath(resolve(`${workspace}/.jj`, (await readFile(`${workspace}/.jj/repo`, "utf8")).trim()))) !== (await realpath(`${archive}/.jj/repo`)) ||
        (await jj(["workspace", "root"], workspace, { readOnly: true }, execution)) !== workspace) {
      throw new Error(`${workspace} is not a colocated workspace of ${archive}; refusing to change it`);
    }
  }

  let createdArchive: RefreshResult = { changed: false, notices: [] };
  if (!archiveEntry) {
    // The workspace admission check happens before any clone or fetch.
    createdArchive = await refreshArchive({ ...options, dest: archive }, execution);
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
      throw new Error(`${branch || "HEAD"}@${remote} is unavailable in ${archive}; fetch it before creating ${workspace}`);
    }
    await mkdir(dirname(workspace), { recursive: true });
    await jj(["workspace", "add", "--colocate", "--revision", `${branch}@${remote}`, workspace], archive, undefined, execution);
  }
  const result = await refreshArchive({ ...options, dest: workspace }, execution);
  return {
    changed: createdArchive.changed || !existing || result.changed,
    notices: [
      ...createdArchive.notices,
      ...(!existing ? [{ kind: "notice" as const, message: `created jj workspace ${workspace} backed by ${archive}` }] : []),
      ...result.notices,
    ],
  };
}
