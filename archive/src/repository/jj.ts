/** The only shell boundary for jj; never interpolate user arguments into a shell. */
import { execFile } from "node:child_process";
import { stat } from "node:fs/promises";
import { promisify } from "node:util";

const exec = promisify(execFile);

export class JjError extends Error {
  public readonly args: string[];
  public readonly detail: string;
  public constructor(args: string[], detail: string) {
    super(`jj ${args.join(" ")}: ${detail}`);
    this.args = args;
    this.detail = detail;
  }
}

export async function jj(args: string[], cwd?: string): Promise<string> {
  try {
    const { stdout } = await exec("jj", ["--no-pager", "--color=never", ...args], {
      cwd,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    return stdout.trim();
  } catch (error) {
    const detail =
      typeof (error as { stderr?: unknown }).stderr === "string"
        ? (error as { stderr: string }).stderr.trim()
        : String(error);
    throw new JjError(args, detail);
  }
}

export function lines(output: string): string[] {
  return output === "" ? [] : output.split("\n").filter(Boolean);
}

export async function exists(path: string): Promise<boolean> {
  return (await stat(path, { throwIfNoEntry: false })) !== undefined;
}

export async function isDirectory(path: string): Promise<boolean> {
  const info = await stat(path, { throwIfNoEntry: false });
  return info !== undefined && info.isDirectory();
}

export const REF_TEMPLATE: string =
  'name ++ "\\t" ++ if(remote,remote,"-") ++ "\\t" ++ ' +
  'if(normal_target,normal_target.commit_id(),"conflict") ++ "\\t" ++ tracked ++ "\\n"';
export const COMMIT_TEMPLATE: string =
  'commit_id ++ "\\t" ++ empty ++ "\\t" ++ ' +
  'parents.map(|c| c.commit_id()).join(",") ++ "\\t" ++ conflict ++ "\\n"';
export const HEAD_TEMPLATE = 'commit_id ++ "\\n"';

export type BookmarkRef = { name: string; remote: string; target: string; tracked: boolean };
export const refKey = (name: string, remote: string): string => `${name}\t${remote}`;

export async function refs(dest: string): Promise<Map<string, BookmarkRef>> {
  const result = new Map<string, BookmarkRef>();
  for (const line of lines(
    await jj(["bookmark", "list", "--all-remotes", "-T", REF_TEMPLATE], dest),
  )) {
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

export type Revision = { commit: string; empty: boolean; parents: string[]; conflict: boolean };

export async function revision(dest: string, rev: string): Promise<Revision> {
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

export async function ancestor(dest: string, older: string, newer: string): Promise<boolean> {
  return Number(await jj(["log", "-r", `${older}::${newer}`, "--count"], dest)) > 0;
}
