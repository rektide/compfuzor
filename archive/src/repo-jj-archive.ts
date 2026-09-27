#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/**
 * Refresh a canonical archive without using Git's worktree-resetting update path.
 *
 * Stdout is one JSON result for Ansible; jj diagnostics and failures go to stderr.
 * Only run this on a checkout whose working tree is not being edited concurrently.
 */

import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdir, realpath, stat } from "node:fs/promises";
import { dirname, join } from "node:path";
import { parseArgs, promisify } from "node:util";

const exec = promisify(execFile);

const USAGE = `Usage: repo-jj-archive.ts --dest DEST --repo URL --label LABEL [--remotes JSON]
                    [--remote NAME] [--version VERSION] [--depth N] [--submodules]
                    [--update true|false]

Refresh a canonical jj-colocated archive without Git's worktree-resetting update
path. Stdout is one JSON result for Ansible; jj diagnostics and failures go to
stderr. Only run this on a checkout whose working tree is not being edited
concurrently.`;

const REF_TEMPLATE =
  'name ++ "\\t" ++ if(remote,remote,"-") ++ "\\t" ++ ' +
  'if(normal_target,normal_target.commit_id(),"conflict") ++ "\\t" ++ tracked ++ "\\n"';
const COMMIT_TEMPLATE =
  'commit_id ++ "\\t" ++ empty ++ "\\t" ++ ' +
  'parents.map(|c| c.commit_id()).join(",") ++ "\\t" ++ conflict ++ "\\n"';
const HEAD_TEMPLATE = 'commit_id ++ "\\n"';
const REMOTE_NAME = /[A-Za-z0-9][A-Za-z0-9._-]*/;

/** Python re.fullmatch parity: the pattern must consume the entire text. */
function fullmatch(pattern: RegExp, text: string): boolean {
  const match = pattern.exec(text);
  return match !== null && match[0] === text;
}

/** Python str.splitlines() parity for newline-terminated jj template output. */
function lines(output: string): string[] {
  return output === "" ? [] : output.split("\n");
}

async function jj(args: string[], cwd?: string): Promise<string> {
  const command = ["jj", "--no-pager", "--color=never", ...args];
  try {
    const { stdout } = await exec(command[0], command.slice(1), {
      cwd,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    return stdout.trim();
  } catch (error) {
    const detail =
      typeof (error as { stderr?: unknown }).stderr === "string"
        ? (error as { stderr: string }).stderr
        : "";
    throw new Error(`${command.join(" ")}: ${detail.trim()}`);
  }
}

type BookmarkRef = {
  name: string;
  remote: string;
  target: string;
  tracked: boolean;
};

const refKey = (name: string, remote: string): string => `${name}\t${remote}`;

async function refs(dest: string): Promise<Map<string, BookmarkRef>> {
  const result = new Map<string, BookmarkRef>();
  const output = await jj(["bookmark", "list", "--all-remotes", "-T", REF_TEMPLATE], dest);
  for (const line of lines(output)) {
    const parts = line.split("\t");
    if (parts.length !== 4) throw new Error(`malformed bookmark line: ${line}`);
    result.set(refKey(parts[0], parts[1]), {
      name: parts[0],
      remote: parts[1],
      target: parts[2],
      tracked: parts[3] === "true",
    });
  }
  return result;
}

type Revision = {
  commit: string;
  empty: boolean;
  parents: string[];
  conflict: boolean;
};

async function revision(dest: string, rev: string): Promise<Revision> {
  const output = await jj(["log", "-G", "-r", rev, "-T", COMMIT_TEMPLATE], dest);
  const parts = output.split("\t");
  if (parts.length !== 4) throw new Error(`malformed revision line for ${rev}: ${output}`);
  return {
    commit: parts[0],
    empty: parts[1] === "true",
    parents: parts[2] === "" ? [] : parts[2].split(","),
    conflict: parts[3] === "true",
  };
}

async function ancestor(dest: string, older: string, newer: string): Promise<boolean> {
  return Number(await jj(["log", "-r", `${older}::${newer}`, "--count"], dest)) > 0;
}

async function exists(path: string): Promise<boolean> {
  return (await stat(path, { throwIfNoEntry: false })) !== undefined;
}

async function isDirectory(path: string): Promise<boolean> {
  const info = await stat(path, { throwIfNoEntry: false });
  return info !== undefined && info.isDirectory();
}

type Notice = { kind: string; name?: string; target?: string; message?: string };

export async function main(): Promise<void> {
  const { values } = parseArgs({
    args: process.argv.slice(2),
    strict: true,
    options: {
      help: { type: "boolean", short: "h", default: false },
      dest: { type: "string" },
      repo: { type: "string" },
      remotes: { type: "string" },
      remote: { type: "string", default: "origin" },
      version: { type: "string", default: "HEAD" },
      label: { type: "string" },
      depth: { type: "string" },
      submodules: { type: "boolean", default: false },
      update: { type: "string", default: "true" },
    },
  });
  if (values.help) {
    console.log(USAGE);
    return;
  }
  const required = (name: string, value: string | undefined): string => {
    if (value === undefined) throw new Error(`the following arguments are required: --${name}`);
    return value;
  };
  const dest = required("dest", values.dest);
  const repo = required("repo", values.repo);
  const remotesArg = required("remotes", values.remotes);
  const labelArg = required("label", values.label);
  if (values.update !== "true" && values.update !== "false") {
    throw new Error(
      `argument --update: invalid choice: '${values.update}' (choose from 'true', 'false')`,
    );
  }
  const update = values.update;
  const remotesJson: unknown = JSON.parse(remotesArg);
  if (remotesJson === null || typeof remotesJson !== "object" || Array.isArray(remotesJson)) {
    throw new Error("--remotes must be a JSON object mapping remote names to URLs");
  }
  const declared = new Map<string, unknown>([["origin", repo]]);
  for (const [name, url] of Object.entries(remotesJson)) declared.set(name, url);
  let version = values.version;
  let selected = values.remote;
  const marker = version.lastIndexOf("@");
  if (marker !== -1 && declared.has(version.slice(marker + 1))) {
    selected = version.slice(marker + 1);
    version = version.slice(0, marker);
  }
  if (!declared.has(selected)) {
    throw new Error(`selected remote '${selected}' is not declared`);
  }
  const urls = new Map<string, string>();
  for (const [name, url] of declared) {
    if (!fullmatch(REMOTE_NAME, name) || typeof url !== "string" || url === "") {
      throw new Error("remote names or URLs are invalid");
    }
    urls.set(name, url);
  }
  if (values.submodules) {
    throw new Error(
      "GIT_SUBMODULES requires explicit submodule safety handling; disable it for this archive render",
    );
  }
  const depth = values.depth === undefined ? undefined : Number(values.depth);
  if (depth !== undefined && (!Number.isInteger(depth) || depth < 1)) {
    throw new Error("GIT_DEPTH must be positive");
  }
  const label =
    labelArg.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^[.-]+|[.-]+$/g, "") || "deployment";
  const now = new Date();
  const pad = (value: number): string => String(value).padStart(2, "0");
  const stamp =
    `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}` +
    `-${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
  const notices: Notice[] = [];
  let changed = false;
  let cloned = false;

  const harvest = async (kind: string, target: string, copy = false): Promise<void> => {
    let commit = target;
    if (copy) {
      // A bookmark on @ itself follows its change ID when the user
      // subsequently edits the worktree. Duplicate under a new change
      // ID so this snapshot cannot drift with future @ rewrites.
      const heads = new Set(
        lines(await jj(["log", "-G", "-r", "heads(all())", "-T", HEAD_TEMPLATE], dest)),
      );
      await jj(["duplicate", "-r", target], dest);
      const newHeads = lines(
        await jj(["log", "-G", "-r", "heads(all())", "-T", HEAD_TEMPLATE], dest),
      ).filter((head) => !heads.has(head));
      if (newHeads.length !== 1) {
        throw new Error(`expected one duplicated jj snapshot; found [${newHeads.join(", ")}]`);
      }
      commit = newHeads[0];
    }
    const name = `harvest/${label}/${kind}-${stamp}-${randomUUID().replaceAll("-", "").slice(0, 8)}`;
    await jj(["bookmark", "create", name, "-r", commit], dest);
    notices.push({ kind: "bookmark-created", name, target: commit });
    changed = true;
  };

  if (!(await exists(dest))) {
    await mkdir(dirname(dest), { recursive: true });
    const command = ["git", "clone", "--colocate", "--remote", selected];
    if (depth !== undefined) command.push("--depth", String(depth));
    if (version !== "HEAD") command.push("--branch", version);
    await jj([...command, urls.get(selected) as string, dest], dirname(dest));
    notices.push({ kind: "notice", message: `cloned jj-colocated archive ${dest}` });
    changed = true;
    cloned = true;
  } else if (!(await isDirectory(dest)) || !(await exists(join(dest, ".git")))) {
    throw new Error(`${dest} exists but is not a colocated Git checkout; refusing to replace it`);
  } else if (!(await exists(join(dest, ".jj")))) {
    await jj(["git", "init", "--git-repo", join(dest, ".git"), dest], dest);
    notices.push({ kind: "notice", message: `adopted existing Git archive into jj: ${dest}` });
    changed = true;
  }

  // This snapshots tracked/untracked changes and imports local Git branches.
  // Do not continue to fetch if jj cannot snapshot the worktree.
  await jj(["status"], dest);
  const before = await refs(dest);
  const working = await revision(dest, "@");
  const work = working.commit;
  const empty = working.empty;
  const parents = working.parents;

  const remoteUrls = new Map<string, string>();
  for (const line of lines(await jj(["git", "remote", "list"], dest))) {
    const space = line.indexOf(" ");
    remoteUrls.set(
      space === -1 ? line : line.slice(0, space),
      space === -1 ? "" : line.slice(space + 1),
    );
  }
  for (const [name, url] of urls) {
    if (!remoteUrls.has(name)) {
      await jj(["git", "remote", "add", name, url], dest);
      changed = true;
    } else if (remoteUrls.get(name) !== url) {
      await jj(["git", "remote", "set-url", name, url], dest);
      changed = true;
    }
  }

  if (update === "false" && before.size > 0) {
    console.log(JSON.stringify({ changed, notices }));
    return;
  }

  // HEAD is the conventional base. Explicit versions select branch bookmarks.
  // For an initial clone, fetch is still necessary for extra remotes/branches.
  // A dirty @ is already a jj commit. Do not mint repeated recovery names
  // for the same revision on consecutive renders without an upstream change.
  let recoveryCovered = false;
  if (!empty) {
    for (const ref of before.values()) {
      if (!ref.name.startsWith(`harvest/${label}/working-copy-`) || ref.remote !== "-") continue;
      if ((await revision(dest, ref.target)).parents.join(",") !== parents.join(",")) continue;
      if ((await jj(["diff", "--from", ref.target, "--to", "@", "--summary"], dest)) !== "")
        continue;
      recoveryCovered = true;
      break;
    }
  }
  if (!empty && !recoveryCovered) {
    await harvest("working-copy", work, true);
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
  for (const name of urls.keys()) {
    await jj(
      ["--config", "git.abandon-unreachable-commits=false", "git", "fetch", "--remote", name],
      dest,
    );
  }
  const after = await refs(dest);
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

  if (oldBase !== null && oldBase !== upstream && !(await ancestor(dest, oldBase, upstream))) {
    await harvest(base.replaceAll("/", "-"), oldBase);
  }
  if (oldBase !== upstream) {
    await jj(["bookmark", "set", "-B", "-r", upstream, base], dest);
    if (oldBase === null) {
      notices.push({ kind: "bookmark-created", name: base, target: upstream });
    } else {
      notices.push({ kind: "notice", message: `${base} -> ${upstream} (${selected})` });
    }
    changed = true;
  } else if (cloned) {
    notices.push({ kind: "bookmark-created", name: base, target: upstream });
  }
  await jj(["bookmark", "track", base, "--remote", selected], dest);

  // Fetch may have changed the current revision only if external Git refs
  // rewrote it; never assume jj's automatic rebase imported the right state.
  const current = await revision(dest, "@");
  if (
    oldBase === current.commit &&
    oldBase !== upstream &&
    (await ancestor(dest, upstream, current.commit))
  ) {
    // Local @ was itself the ahead base. Keep it as a fixed, bookmarked
    // parent before the next user edit can rewrite that old base tip.
    await jj(["new", "@"], dest);
    changed = true;
  } else if (!(await ancestor(dest, upstream, current.commit))) {
    if (
      current.empty &&
      oldBase !== null &&
      current.parents.join(",") === oldBase &&
      (await ancestor(dest, oldBase, upstream))
    ) {
      await jj(["rebase", "-r", "@", "-d", base], dest);
    } else {
      // Never rewrite a bookmarked dirty @: jj moves bookmarks with a
      // rewritten change. A merge keeps the exact pre-fetch worktree as
      // its first parent, and exposes any conflicts for the operator.
      if (empty && current.commit !== work) {
        await harvest("head", work);
      }
      await jj(["new", "@", base], dest);
    }
    changed = true;
    notices.push({ kind: "notice", message: `merged local checkout with ${base}@${selected}` });
  }
  if ((await revision(dest, "@")).conflict) {
    notices.push({
      kind: "notice",
      message: "working copy has merge conflicts; resolve them before building",
    });
  }
  if ((before.get(refKey(base, selected))?.target ?? null) !== upstream) {
    changed = true;
  }
  console.log(JSON.stringify({ changed, notices }));
}

const argvPath = process.argv[1];
if (argvPath) {
  realpath(argvPath).then(
    (realArgv) => {
      if (realArgv !== import.meta.filename) return;
      return main().catch((error: unknown) => {
        console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
        process.exitCode = 1;
      });
    },
    (error: unknown) => {
      console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
      process.exitCode = 1;
    },
  );
}
