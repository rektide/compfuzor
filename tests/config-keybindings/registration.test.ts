import { expect, test } from "vitest";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { withInputBatch } from "../../files/config/registration.ts";

test("cross-record donor and symlink-chain collisions fail before any registration changes", async () => {
  const scratch = resolve(".test-agent/keybinding-registration");
  await mkdir(scratch, { recursive: true });
  await writeFile(join(scratch, "README.md"), "# Registration scratch\nIsolated preflight collision tests.\n", { flag: "wx" }).catch((error: NodeJS.ErrnoException) => { if (error.code !== "EEXIST") throw error; });
  const root = await mkdtemp(join(scratch, "batch-"));
  try {
    const first = join(root, "first"); const later = join(root, "later"); const output = join(root, "output");
    await writeFile(first, "first"); await writeFile(later, "later"); await writeFile(output, "old");
    const run = (source: string) => withInputBatch([
      { source: first, destination: later, strategy: "copy" },
      { source, destination: output, strategy: "link" },
    ], async () => { throw new Error("callback must not run"); }, { success: () => true, workspaceRoot: scratch });
    await expect(run(later)).rejects.toThrow("batch donor");
    const alias = join(root, "alias"); await symlink(later, alias);
    await expect(run(alias)).rejects.toThrow("batch donor");
    expect(await readFile(later, "utf8")).toBe("later"); expect(await readFile(output, "utf8")).toBe("old");
  } finally { await rm(root, { recursive: true, force: true }); }
});
