import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmod, copyFile, mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { test } from "node:test";
import { jj, JjError } from "../../src/repository/jj.ts";

const scratchRoot = resolve(import.meta.dirname, "../../../.test-agent/archive-cancellation");
const sourceEntry = resolve(import.meta.dirname, "../../src/repo-jj-archive.ts");
const launcherEntry = resolve(import.meta.dirname, "../../../script/repo-jj-archive.ts");
const bundleEntry = resolve(import.meta.dirname, "../../repo-jj-archive.ts");

test("jj Promise facade rejects an already-aborted signal without spawning", async (t) => {
  await mkdir(scratchRoot, { recursive: true });
  const dir = await mkdtemp(join(scratchRoot, "aborted-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(jj(["status"], dir, undefined, { signal: controller.signal }), (error) => {
    assert.ok(error instanceof JjError);
    assert.equal(error.detail, "interrupted");
    return true;
  });
});

const executableEntries = [
  { name: "source entry", path: sourceEntry },
  { name: "launcher", path: launcherEntry },
  { name: "copied standalone bundle", path: null },
] as const;

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  for (const entry of executableEntries) {
    test(`${entry.name} ${signal} interrupts jj and discards stdout`, async (t) => {
      await mkdir(scratchRoot, { recursive: true });
      const dir = await mkdtemp(join(scratchRoot, "signal-"));
      t.after(() => rm(dir, { recursive: true, force: true }));

      let executable = entry.path;
      if (executable === null) {
        // Keep the copied .ts outside the repository's package scope and
        // node_modules ancestry: the artifact must carry every JS dependency.
        const standalone = await mkdtemp(join(tmpdir(), "repo-jj-archive-standalone-"));
        t.after(() => rm(standalone, { recursive: true, force: true }));
        executable = join(standalone, "repo-jj-archive.ts");
        await copyFile(bundleEntry, executable);
        await chmod(executable, 0o755);
        for (let parent = resolve(standalone); ;) {
          assert.equal(
            await stat(join(parent, "package.json"), { throwIfNoEntry: false }),
            undefined,
            `unexpected package.json in standalone ancestry: ${parent}`,
          );
          assert.equal(
            await stat(join(parent, "node_modules"), { throwIfNoEntry: false }),
            undefined,
            `unexpected node_modules in standalone ancestry: ${parent}`,
          );
          const next = resolve(parent, "..");
          if (next === parent) break;
          parent = next;
        }
      }

      const bin = join(dir, "bin");
      await mkdir(bin);
      const pidFile = join(dir, "jj.pid");
      const mutation = join(dir, "mutated");
      const fake = join(bin, "jj");
      await writeFile(
        fake,
        `#!/usr/bin/env node
import fs from 'node:fs';
fs.writeFileSync(process.env.FAKE_JJ_PID, String(process.pid));
setTimeout(() => { fs.writeFileSync(process.env.FAKE_JJ_MUTATION, 'late'); process.exit(0); }, 800);
`,
      );
      await chmod(fake, 0o755);
      // fake jj waits instead of reaching Git or the network; SIGINT/SIGTERM
      // must kill that child through each shipped executable entry point.
      const child = spawn(
        executable,
        [
          "refresh",
          "--json",
          "--dest",
          join(dir, "checkout"),
          "--repo",
          "file:///fake/repo",
          "--remotes",
          "{}",
          "--label",
          "probe",
        ],
        {
          cwd: dir,
          env: {
            ...process.env,
            PATH: `${bin}:${process.env.PATH ?? ""}`,
            FAKE_JJ_PID: pidFile,
            FAKE_JJ_MUTATION: mutation,
          },
          stdio: ["ignore", "pipe", "pipe"],
        },
      );
      let stdout = "";
      let stderr = "";
      child.stdout.setEncoding("utf8").on("data", (chunk: string) => {
        stdout += chunk;
      });
      child.stderr.setEncoding("utf8").on("data", (chunk: string) => {
        stderr += chunk;
      });
      t.after(() => {
        if (child.exitCode === null) child.kill("SIGKILL");
      });
      const exit = new Promise<number | null>((resolveExit, reject) => {
        child.once("error", reject);
        child.once("close", (code) => resolveExit(code));
      });
      let pid: number | undefined;
      for (let attempt = 0; attempt < 100; attempt++) {
        pid = await readFile(pidFile, "utf8").then(Number, () => undefined);
        if (pid !== undefined) break;
        if (child.exitCode !== null) break;
        await delay(20);
      }
      assert.ok(pid, `fake jj did not spawn: ${stderr}`);
      child.kill(signal);
      const code = await Promise.race([
        exit,
        delay(4000).then(() => {
          throw new Error(`CLI hung after ${signal}`);
        }),
      ]);
      assert.equal(code, 130, stderr);
      assert.equal(stdout, "", "interrupted machine output must remain empty");
      // The fixture waits long enough to write a marker if orphaned. A dead
      // child cannot perform that mutation even after its parent exits.
      await delay(1000);
      assert.equal(
        await readFile(mutation, "utf8").then(
          () => true,
          () => false,
        ),
        false,
      );
      assert.throws(() => process.kill(pid, 0), { code: "ESRCH" });
    });
  }
}
