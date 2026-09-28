/** Real Git/jj adoption: append-only receipt/pins and exact same-input resume. */
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import { setTimeout as delay } from "node:timers/promises";
import { test } from "node:test";
import { Effect } from "effect";
import { applyAdoption } from "../../src/custody/apply.ts";
import { planAdoption } from "../../src/custody/inventory.ts";
import type { AdoptInput } from "../../src/custody/model.ts";

const exec = promisify(execFile);
const root = join(import.meta.dirname, "../../../.test-agent/custody-apply/tests");

async function command(program: string, args: string[], cwd?: string): Promise<string> {
  const { stdout } = await exec(program, args, {
    cwd,
    maxBuffer: 64 * 1024 * 1024,
    env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_SYSTEM: "/dev/null" },
  });
  return stdout.toString().trim();
}
const git = (cwd: string, ...args: string[]) => command("git", args, cwd);

async function fixture(name: string): Promise<{ source: string; dest: string; input: AdoptInput }> {
  const dir = join(root, name);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  const source = join(dir, "source");
  await mkdir(source);
  await git(source, "init", "--quiet", "-b", "main");
  await git(source, "config", "user.name", "custody fixture");
  await git(source, "config", "user.email", "fixture@example.invalid");
  await writeFile(join(source, "tracked.txt"), "original\n");
  await git(source, "add", "tracked.txt");
  await git(source, "commit", "--quiet", "-m", "initial");
  await git(source, "tag", "-a", "signed-off", "-m", "historical tag");
  await git(source, "tag", "plain");
  const dest = join(dir, "destination");
  await command("git", ["clone", "--quiet", "--no-hardlinks", source, dest]);
  await command("jj", ["git", "init", "--colocate", "--quiet"], dest);
  return {
    source,
    dest,
    input: {
      legacy: source,
      dest,
      repo: source,
      branch: "main",
      label: "legacy",
      generation: "g0",
      excludeFrom: null,
      dispositions: null,
      pathReview: null,
    },
  };
}

async function digestTree(dir: string): Promise<string> {
  const parts: string[] = [];
  const walk = async (path: string, prefix = ""): Promise<void> => {
    for (const entry of await readdir(path, { withFileTypes: true })) {
      const name = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) await walk(join(path, entry.name), name);
      else if (entry.isFile())
        parts.push(
          `${name}:${createHash("sha256")
            .update(await readFile(join(path, entry.name)))
            .digest("hex")}`,
        );
    }
  };
  await walk(dir);
  return createHash("sha256").update(parts.sort().join("\n")).digest("hex");
}

void test("clean apply preserves both worktrees and the source ODB; retry reuses the exact receipt and vault", async () => {
  const { source, dest, input } = await fixture("clean-retry");
  const beforeSource = await digestTree(source);
  const beforeDest = await readFile(join(dest, "tracked.txt"));
  const first = await Effect.runPromise(applyAdoption(input));
  assert.equal(first.changed, true);
  assert.equal(first.verification.custodyVerified, true);
  assert.equal(await digestTree(source), beforeSource);
  assert.deepEqual(await readFile(join(dest, "tracked.txt")), beforeDest);
  const second = await Effect.runPromise(applyAdoption(input));
  assert.equal(second.changed, false);
  assert.equal(second.receiptCommitOid, first.receiptCommitOid);
  assert.deepEqual(await readFile(join(dest, "tracked.txt")), beforeDest);
  assert.equal(await digestTree(source), beforeSource);
  assert.equal(await git(dest, "rev-parse", first.receiptRef), first.receiptCommitOid);
});

void test("changed source after a completed generation cannot replace its receipt", async () => {
  const { source, dest, input } = await fixture("changed-source");
  const first = await Effect.runPromise(applyAdoption(input));
  await writeFile(join(source, "tracked.txt"), "new source generation\n");
  await git(source, "add", "tracked.txt");
  await git(source, "commit", "--quiet", "-m", "later");
  await assert.rejects(() => Effect.runPromise(applyAdoption(input)));
  assert.equal(await git(dest, "rev-parse", first.receiptRef), first.receiptCommitOid);
});

void test("dirty checkout captures reviewed synthetic tree privately and retries without source writes", async () => {
  const { source, dest, input } = await fixture("dirty-snapshot");
  await writeFile(join(source, "tracked.txt"), "changed working tree\n");
  await writeFile(join(source, "untracked.txt"), "new untracked data\n");
  const beforeSource = await digestTree(source);
  const beforeCheckout = await readFile(join(dest, "tracked.txt"));
  const first = await Effect.runPromise(applyAdoption(input));
  assert.equal(first.verification.custodyVerified, true);
  assert.equal(await digestTree(source), beforeSource);
  assert.deepEqual(await readFile(join(dest, "tracked.txt")), beforeCheckout);
  const retry = await Effect.runPromise(applyAdoption(input));
  assert.equal(retry.changed, false);
  assert.equal(retry.receiptCommitOid, first.receiptCommitOid);
  assert.equal(await digestTree(source), beforeSource);
});

void test("sensitive dirty snapshot requires exact manifest-bound path review, never a bypass", async () => {
  const { source, dest, input } = await fixture("reviewed-sensitive");
  await writeFile(join(source, ".env"), "SECRET=original\n");
  await git(source, "add", "-f", ".env");
  await git(source, "commit", "--quiet", "-m", "credential fixture");
  // Clone again after the sensitive HEAD is established so this fixture's
  // destination has the same declared origin and clean historical baseline.
  await rm(dest, { recursive: true, force: true });
  await command("git", ["clone", "--quiet", "--no-hardlinks", source, dest]);
  await command("jj", ["git", "init", "--colocate", "--quiet"], dest);
  await writeFile(join(source, ".env"), "SECRET=changed\n");
  const unreviewed = await Effect.runPromise(planAdoption(input));
  assert.equal(unreviewed.state, "blocked");
  assert.ok(unreviewed.blockers.some(({ code }) => code === "path-review-required"));
  const proposal = unreviewed.proposedSnapshot;
  assert.ok(proposal);
  const file = proposal.paths.find(({ path }) => path === ".env");
  assert.ok(file);
  const reviewPath = join(dirname(dest), "path-review.json");
  await writeFile(
    reviewPath,
    JSON.stringify({
      schema: "compfuzor.archive-path-review/v1",
      manifestSha256: proposal.manifestSha256,
      included: [
        {
          ...file,
          classification: "credential",
          decision: "local-custody-approved",
          reason: "private archival custody",
        },
      ],
      stagedVsUnstaged: null,
    }),
  );
  const reviewed = { ...input, pathReview: reviewPath };
  const ready = await Effect.runPromise(planAdoption(reviewed));
  assert.equal(ready.state, "ready");
  const before = await digestTree(source);
  const applied = await Effect.runPromise(applyAdoption(reviewed));
  assert.equal(applied.verification.custodyVerified, true);
  assert.equal(await digestTree(source), before);
});

void test("staged/unstaged split requires explicit single-tree review before apply", async () => {
  const { source, dest, input } = await fixture("split-review");
  await writeFile(join(source, "tracked.txt"), "staged version\n");
  await git(source, "add", "tracked.txt");
  await writeFile(join(source, "tracked.txt"), "unstaged version\n");
  const blocked = await Effect.runPromise(planAdoption(input));
  assert.equal(blocked.state, "blocked");
  assert.ok(blocked.blockers.some(({ code }) => code === "path-review-required"));
  assert.ok(blocked.proposedSnapshot);
  const reviewPath = join(dirname(dest), "split-review.json");
  await writeFile(
    reviewPath,
    JSON.stringify({
      schema: "compfuzor.archive-path-review/v1",
      manifestSha256: blocked.proposedSnapshot.manifestSha256,
      included: [],
      stagedVsUnstaged: {
        decision: "single-tree-approved",
        reason: "explicitly accept one synthetic tree",
      },
    }),
  );
  const reviewed = { ...input, pathReview: reviewPath };
  const before = await digestTree(source);
  const result = await Effect.runPromise(applyAdoption(reviewed));
  assert.equal(result.verification.custodyVerified, true);
  assert.equal(await digestTree(source), before);
});

void test("same-input retry completes a missing pin without minting a second vault", async () => {
  const { source, dest, input } = await fixture("missing-pin");
  const first = await Effect.runPromise(applyAdoption(input));
  const ref = (
    await git(dest, "for-each-ref", "--format=%(refname)", "refs/heads/harvest/legacy/g0/branch")
  ).split("\n")[0];
  assert.ok(ref.startsWith("refs/heads/harvest/legacy/g0/branch/"));
  const target = await git(dest, "rev-parse", ref);
  // The fixture deliberately models an interrupted transaction; production
  // orchestration never deletes or reconciles a custody ref.
  await git(dest, "update-ref", "-d", ref);
  const second = await Effect.runPromise(applyAdoption(input));
  assert.equal(second.changed, true);
  assert.equal(second.receiptCommitOid, first.receiptCommitOid);
  assert.equal(await git(dest, "rev-parse", ref), target);
  const vaultRoot = join(dirname(dest), ".compfuzor-adoptions");
  const archiveIds = await readdir(vaultRoot);
  assert.equal(archiveIds.length, 1);
  assert.equal((await readdir(join(vaultRoot, archiveIds[0]))).length, 1);
  assert.equal(await git(dest, "rev-parse", first.receiptRef), first.receiptCommitOid);
  assert.ok((await digestTree(source)).length > 0);
});

void test("interruption after durable seal installs no refs; retry can finish", async () => {
  const { dest, input } = await fixture("seal-interrupt");
  await assert.rejects(() =>
    Effect.runPromise(
      applyAdoption(input, {
        afterSeal: async () => {
          throw new Error("simulated interruption");
        },
      }),
    ),
  );
  await assert.rejects(() => git(dest, "rev-parse", "refs/adopt/receipts/legacy/g0"));
  const resumed = await Effect.runPromise(applyAdoption(input));
  assert.equal(resumed.verification.custodyVerified, true);
});

void test("aborting the Effect after seal leaves the vault but never starts destination transfer", async () => {
  const { dest, input } = await fixture("abort-after-seal");
  const controller = new AbortController();
  await assert.rejects(() =>
    Effect.runPromise(
      applyAdoption(input, {
        afterSeal: async () => {
          controller.abort(new Error("abort before destination transfer"));
        },
      }),
      { signal: controller.signal },
    ),
  );
  const vault = join(dirname(dest), ".compfuzor-adoptions");
  assert.equal((await readdir(vault)).length, 1);
  await assert.rejects(() => git(dest, "rev-parse", "refs/adopt/receipts/legacy/g0"));
  const resumed = await Effect.runPromise(applyAdoption(input));
  assert.equal(resumed.verification.custodyVerified, true);
});

void test("abort kills a blocked destination update-ref child and never starts verification", async () => {
  const { dest, input } = await fixture("abort-update-ref");
  const toolDir = join(dirname(dest), "git-wrapper");
  await mkdir(toolDir);
  const marker = join(toolDir, "update-ref.pid");
  await writeFile(
    join(toolDir, "git"),
    [
      "#!/bin/sh",
      'if [ "$PWD" = "$CUSTODY_TEST_DEST" ]; then',
      '  for arg in "$@"; do',
      '    if [ "$arg" = "update-ref" ]; then',
      '      printf "%s\\n" "$$" > "$CUSTODY_TEST_MARKER"',
      "      exec sleep 30",
      "    fi",
      "  done",
      "fi",
      'exec "$CUSTODY_TEST_REAL_GIT" "$@"',
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  const originalPath = process.env.PATH;
  const originalDest = process.env.CUSTODY_TEST_DEST;
  const originalMarker = process.env.CUSTODY_TEST_MARKER;
  const originalGit = process.env.CUSTODY_TEST_REAL_GIT;
  const actualGit = await command("which", ["git"]);
  const controller = new AbortController();
  let verified = false;
  let observedPid: number | null = null;
  const watch = async (): Promise<void> => {
    for (let attempt = 0; attempt < 150; attempt++) {
      const text = await readFile(marker, "utf8").catch(() => null);
      if (text !== null) {
        observedPid = Number(text.trim());
        controller.abort(new Error("abort blocked update-ref"));
        return;
      }
      await delay(20);
    }
    controller.abort(new Error("update-ref wrapper did not start"));
  };
  try {
    process.env.PATH = `${toolDir}:${originalPath}`;
    process.env.CUSTODY_TEST_DEST = dest;
    process.env.CUSTODY_TEST_MARKER = marker;
    process.env.CUSTODY_TEST_REAL_GIT = actualGit;
    const watching = watch();
    await assert.rejects(() =>
      Effect.runPromise(
        applyAdoption(input, {
          afterInstall: async () => {
            verified = true;
          },
        }),
        { signal: controller.signal },
      ),
    );
    await watching;
    assert.equal(verified, false);
    const pid = observedPid;
    if (pid === null) throw new Error("blocked update-ref did not start before abort");
    // Effect's scoped child spawner must reap/terminate the actual process,
    // not merely reject the outer Promise while update-ref runs detached.
    for (let attempt = 0; attempt < 50; attempt++) {
      try {
        process.kill(pid, 0);
      } catch {
        break;
      }
      await delay(20);
    }
    assert.throws(() => process.kill(pid, 0), { code: "ESRCH" });
  } finally {
    process.env.PATH = originalPath;
    if (originalDest === undefined) delete process.env.CUSTODY_TEST_DEST;
    else process.env.CUSTODY_TEST_DEST = originalDest;
    if (originalMarker === undefined) delete process.env.CUSTODY_TEST_MARKER;
    else process.env.CUSTODY_TEST_MARKER = originalMarker;
    if (originalGit === undefined) delete process.env.CUSTODY_TEST_REAL_GIT;
    else process.env.CUSTODY_TEST_REAL_GIT = originalGit;
  }
});

void test("changed destination refs after transfer block installation without removing any ref", async () => {
  const { dest, input } = await fixture("destination-race");
  const original = await git(dest, "rev-parse", "HEAD");
  await assert.rejects(() =>
    Effect.runPromise(
      applyAdoption(input, {
        afterTransfer: () =>
          git(dest, "update-ref", "refs/heads/intruder", original).then(() => undefined),
      }),
    ),
  );
  assert.equal(await git(dest, "rev-parse", "refs/heads/intruder"), original);
  await assert.rejects(() => git(dest, "rev-parse", "refs/adopt/receipts/legacy/g0"));
});

void test("source changed after staging is detected before destination refs are written", async () => {
  const { source, dest, input } = await fixture("source-race");
  await assert.rejects(() =>
    Effect.runPromise(
      applyAdoption(input, {
        afterSeal: () => writeFile(join(source, "tracked.txt"), "changed after seal\n"),
      }),
    ),
  );
  await assert.rejects(() => git(dest, "rev-parse", "refs/adopt/receipts/legacy/g0"));
  assert.equal(await readFile(join(source, "tracked.txt"), "utf8"), "changed after seal\n");
});

void test("missing destination is a named plan blocker; apply never creates an incomplete archive", async () => {
  const { source, dest, input } = await fixture("missing-dest");
  await rm(dest, { recursive: true, force: true });
  const before = await digestTree(source);
  const planned = await Effect.runPromise(planAdoption(input));
  assert.equal(planned.state, "blocked");
  assert.ok(planned.blockers.some(({ code }) => code === "destination-missing"));
  await assert.rejects(() => Effect.runPromise(applyAdoption(input)));
  await assert.rejects(() => readFile(join(dest, "tracked.txt")));
  assert.equal(await digestTree(source), before);
});

void test("occupied receipt namespace is not reinterpreted as a fresh generation", async () => {
  const { dest, input } = await fixture("occupied-receipt");
  const other = await git(dest, "rev-parse", "HEAD");
  const receipt = "refs/adopt/receipts/legacy/g0";
  await git(dest, "update-ref", receipt, other);
  await assert.rejects(() => Effect.runPromise(applyAdoption(input)));
  assert.equal(await git(dest, "rev-parse", receipt), other);
  await assert.rejects(() => readdir(join(dirname(dest), ".compfuzor-adoptions")));
});

void test("new generations add refs without rewriting an older immutable receipt", async () => {
  const { dest, input } = await fixture("two-generations");
  const first = await Effect.runPromise(applyAdoption(input));
  const next = await Effect.runPromise(applyAdoption({ ...input, generation: "g1" }));
  assert.equal(first.verification.custodyVerified, true);
  assert.equal(next.verification.custodyVerified, true);
  assert.notEqual(first.receiptRef, next.receiptRef);
  assert.equal(await git(dest, "rev-parse", first.receiptRef), first.receiptCommitOid);
  assert.equal(await git(dest, "rev-parse", next.receiptRef), next.receiptCommitOid);
});

void test("interrupted verification returns failure; retry verifies original installed receipt", async () => {
  const { dest, input } = await fixture("verify-interrupt");
  await assert.rejects(() =>
    Effect.runPromise(
      applyAdoption(input, {
        afterInstall: async () => {
          throw new Error("verification interrupted");
        },
      }),
    ),
  );
  const original = await git(dest, "rev-parse", "refs/adopt/receipts/legacy/g0");
  const retry = await Effect.runPromise(applyAdoption(input));
  assert.equal(retry.changed, false);
  assert.equal(retry.receiptCommitOid, original);
  assert.equal(retry.verification.custodyVerified, true);
});

void test("destination worktree drift during final verification refuses success but retains immutable refs", async () => {
  const { dest, input } = await fixture("final-destination-drift");
  await assert.rejects(
    () =>
      Effect.runPromise(
        applyAdoption(input, {
          afterInstall: () => writeFile(join(dest, "tracked.txt"), "drift before final proof\n"),
        }),
      ),
    { code: "destination-drift" },
  );
  assert.match(await git(dest, "rev-parse", "refs/adopt/receipts/legacy/g0"), /^[0-9a-f]{40}$/);
  assert.equal(await readFile(join(dest, "tracked.txt"), "utf8"), "drift before final proof\n");
});

void test("source drift during final verification refuses success but retains immutable refs", async () => {
  const { source, dest, input } = await fixture("final-source-drift");
  await assert.rejects(
    () =>
      Effect.runPromise(
        applyAdoption(input, {
          afterInstall: () =>
            writeFile(join(source, "tracked.txt"), "source drift before final proof\n"),
        }),
      ),
    { code: "source-drift" },
  );
  assert.match(await git(dest, "rev-parse", "refs/adopt/receipts/legacy/g0"), /^[0-9a-f]{40}$/);
});
