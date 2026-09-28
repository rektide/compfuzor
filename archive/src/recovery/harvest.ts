import { randomUUID } from "node:crypto";
import { preflight } from "../repository/health.ts";
import { HEAD_TEMPLATE, jj, lines, revision, type BookmarkRef } from "../repository/jj.ts";

export type Notice = { kind: string; name?: string; target?: string; message?: string };

export function stamp(): string {
  const now = new Date();
  const pad = (value: number): string => String(value).padStart(2, "0");
  return (
    `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}` +
    `-${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`
  );
}

export function safeLabel(label: string): string {
  return label.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^[.-]+|[.-]+$/g, "") || "deployment";
}

/** Duplicate a mutable @ so its recovery bookmark cannot drift with subsequent edits. */
export async function harvest(
  dest: string,
  label: string,
  kind: string,
  target: string,
  copy = false,
): Promise<Notice> {
  let commit = target;
  if (copy) {
    await preflight(dest);
    const heads = new Set(
      lines(await jj(["log", "-G", "-r", "heads(all())", "-T", HEAD_TEMPLATE], dest)),
    );
    await jj(["duplicate", "-r", target], dest);
    await preflight(dest);
    const newHeads = lines(
      await jj(["log", "-G", "-r", "heads(all())", "-T", HEAD_TEMPLATE], dest),
    ).filter((head) => !heads.has(head));
    if (newHeads.length !== 1)
      throw new Error(`expected one duplicated jj snapshot; found [${newHeads.join(", ")}]`);
    commit = newHeads[0];
  }
  const name = `harvest/${safeLabel(label)}/${kind}-${stamp()}-${randomUUID().replaceAll("-", "").slice(0, 8)}`;
  await jj(["bookmark", "create", name, "-r", commit], dest);
  return { kind: "bookmark-created", name, target: commit };
}

export async function recoveryCovered(
  dest: string,
  label: string,
  before: Map<string, BookmarkRef>,
  parents: string[],
): Promise<boolean> {
  for (const ref of before.values()) {
    if (!ref.name.startsWith(`harvest/${safeLabel(label)}/working-copy-`) || ref.remote !== "-")
      continue;
    if ((await revision(dest, ref.target)).parents.join(",") !== parents.join(",")) continue;
    if ((await jj(["diff", "--from", ref.target, "--to", "@", "--summary"], dest)) !== "") continue;
    return true;
  }
  return false;
}
