import { homedir } from "node:os";
import { join } from "node:path";
import { exists, jj } from "./jj.ts";

/** Convenience only; compfuzor playbooks always use the launcher in playbook_dir. */
export async function locateCompfuzor(
  freshen: boolean,
  archiveDir?: string,
): Promise<string | null> {
  const root = archiveDir ?? join(homedir(), "archive");
  const path = join(root, "rektide", "compfuzor");
  if (!(await exists(join(path, ".git")))) return null;
  if (freshen) {
    if (!(await exists(join(path, ".jj"))))
      throw new Error(`${path} is not a jj checkout; cannot freshen`);
    await jj(
      ["--config", "git.abandon-unreachable-commits=false", "git", "fetch", "--remote", "origin"],
      path,
    );
  }
  return path;
}
