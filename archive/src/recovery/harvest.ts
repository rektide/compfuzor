import { randomUUID } from "node:crypto";
import { preflight } from "../repository/health.ts";
import {
  HEAD_TEMPLATE,
  jj,
  lines,
  revision,
  type BookmarkRef,
  type ExecutionOptions,
} from "../repository/jj.ts";

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

/** Keep a local branch tip reachable when its tracked upstream diverges. */
export async function saveDisplacedTip(
  dest: string,
  branch: string,
  target: string,
  execution?: ExecutionOptions,
): Promise<Notice> {
  const name = `compfuzor/save/${safeLabel(branch)}-${stamp()}-${randomUUID().replaceAll("-", "").slice(0, 8)}`;
  await jj(["bookmark", "create", name, "-r", target], dest, undefined, execution);
  return { kind: "bookmark-created", name, target };
}

/** Duplicate a mutable @ so its recovery bookmark cannot drift with subsequent edits. */
export async function harvest(
  dest: string,
  label: string,
  kind: string,
  target: string,
  copy = false,
  execution?: ExecutionOptions,
): Promise<Notice> {
  let commit = target;
  if (copy) {
    await preflight(dest, {}, execution);
    const heads = new Set(
      lines(
        await jj(
          ["log", "-G", "-r", "heads(all())", "-T", HEAD_TEMPLATE],
          dest,
          undefined,
          execution,
        ),
      ),
    );
    await jj(["duplicate", "-r", target], dest, undefined, execution);
    await preflight(dest, {}, execution);
    const newHeads = lines(
      await jj(
        ["log", "-G", "-r", "heads(all())", "-T", HEAD_TEMPLATE],
        dest,
        undefined,
        execution,
      ),
    ).filter((head) => !heads.has(head));
    if (newHeads.length !== 1)
      throw new Error(`expected one duplicated jj snapshot; found [${newHeads.join(", ")}]`);
    commit = newHeads[0];
  }
  const name = `harvest/${safeLabel(label)}/${kind}-${stamp()}-${randomUUID().replaceAll("-", "").slice(0, 8)}`;
  await jj(["bookmark", "create", name, "-r", commit], dest, undefined, execution);
  return { kind: "bookmark-created", name, target: commit };
}

export async function recoveryCovered(
  dest: string,
  label: string,
  before: Map<string, BookmarkRef>,
  parents: string[],
  execution?: ExecutionOptions,
): Promise<boolean> {
  for (const ref of before.values()) {
    if (!ref.name.startsWith(`harvest/${safeLabel(label)}/working-copy-`) || ref.remote !== "-")
      continue;
    if ((await revision(dest, ref.target, execution)).parents.join(",") !== parents.join(","))
      continue;
    if (
      (await jj(
        ["diff", "--from", ref.target, "--to", "@", "--summary"],
        dest,
        undefined,
        execution,
      )) !== ""
    )
      continue;
    return true;
  }
  return false;
}
