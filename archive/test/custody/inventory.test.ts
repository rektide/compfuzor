/**
 * Custody inventory/admission tests.
 *
 * Decode tests are pure. Integration tests build disposable Git (and where
 * needed jj-colocated) fixtures under .test-agent/custody-inventory/tests/
 * and prove three things per the custody contracts:
 *
 * 1. admission correctness — clean/detached/dirty/unborn/unsupported
 *    variants produce ready plans or named blockers with observed
 *    (possibly null) inventory categories, never fabricated facts;
 * 2. read-only proof — source `.git`, `.jj`, worktree and destination
 *    fingerprints are byte-identical before and after planning;
 * 3. privacy — plan output carries names/classes/hashes only; secret file
 *    contents never appear in the serialized plan.
 */
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile, readdir, readlink, rm, mkdir, writeFile, symlink } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { test } from "node:test";
import { Effect } from "effect";
import { planAdoption } from "../../src/custody/inventory.ts";
import { applyAdoption } from "../../src/custody/apply.ts";
import { CustodyError } from "../../src/custody/errors.ts";
import type { AdoptInput, PlanV1 } from "../../src/custody/model.ts";
import {
  nulRecords,
  parseBoolean,
  parseCount,
  parseForEachRef,
  parseFsck,
  parseHashObjectLines,
  parseLsFilesStage,
  parseLsTree,
  parseReflogShow,
  parseStatusV2,
  strictUtf8,
} from "../../src/custody/inventory/decode.ts";

const exec = promisify(execFile);
const ROOT = join(import.meta.dirname, "../../../.test-agent/custody-inventory/tests");

async function sh(command: string, args: string[], cwd?: string): Promise<string> {
  const { stdout } = await exec(command, args, {
    cwd,
    maxBuffer: 64 * 1024 * 1024,
    // Fixture commands must not inherit host gitignore/config: the user's
    // global excludes could silently drop fixture files like `.env`.
    env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_SYSTEM: "/dev/null" },
  });
  return stdout.toString().trim();
}

async function git(args: string[], cwd: string): Promise<string> {
  return sh("git", args, cwd);
}

async function writeFileUtf8(path: string, content: string): Promise<void> {
  await writeFile(path, content);
}

/** Byte fingerprint of every file under root (content, or symlink target). */
async function fingerprintTree(root: string): Promise<string> {
  const lines: string[] = [];
  const walk = async (dir: string, prefix: string): Promise<void> => {
    for (const entry of await readdir(dir, { withFileTypes: true }).catch(() => [])) {
      const rel = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) await walk(full, rel);
      else if (entry.isFile())
        lines.push(
          `${rel}\t${createHash("sha256")
            .update(await readFile(full))
            .digest("hex")}`,
        );
      else if (entry.isSymbolicLink()) lines.push(`${rel}\tlink:${await readlink(full)}`);
    }
  };
  await walk(root, "");
  lines.sort();
  return createHash("sha256").update(lines.join("\n")).digest("hex");
}

async function fresh(name: string): Promise<string> {
  const path = join(ROOT, name);
  await rm(path, { recursive: true, force: true });
  await mkdir(path, { recursive: true });
  return path;
}

async function commit(
  dir: string,
  message: string,
  file: string,
  content: string,
): Promise<string> {
  await mkdir(join(dir, file, ".."), { recursive: true });
  await writeFileUtf8(join(dir, file), content);
  // -f: fixture files may match host ignore patterns during setup.
  await git(["add", "-f", file], dir);
  await git(["commit", "--quiet", "-m", message], dir);
  return git(["rev-parse", "HEAD"], dir);
}

async function initRepo(dir: string, branch = "main"): Promise<void> {
  await git(["init", "--quiet", "-b", branch, "."], dir);
  await git(["config", "user.email", "custody@example.invalid"], dir);
  await git(["config", "user.name", "custody test"], dir);
}

/** A jj-colocated clone whose origin url is the source path it mirrors. */
async function makeDest(source: string, name: string): Promise<string> {
  const dest = await fresh(name);
  await sh("git", ["clone", "--quiet", "--no-hardlinks", source, dest]);
  await sh("jj", ["git", "init", "--colocate", "--quiet"], dest);
  return dest;
}

const input = (legacy: string, dest: string, overrides: Partial<AdoptInput> = {}): AdoptInput => ({
  legacy,
  dest,
  repo: legacy,
  branch: "main",
  label: "legacy",
  generation: "g0",
  excludeFrom: null,
  dispositions: null,
  pathReview: null,
  ...overrides,
});

async function plan(withInput: AdoptInput): Promise<PlanV1> {
  return Effect.runPromise(planAdoption(withInput));
}

const codes = (plan: PlanV1): string[] => plan.blockers.map(({ code }) => code);

// ---------------------------------------------------------------- decode

test("nulRecords splits records and rejects interior empties", () => {
  const bytes = new TextEncoder().encode("a\0b\0");
  assert.deepEqual(
    nulRecords(bytes, "test").map((part) => new TextDecoder().decode(part)),
    ["a", "b"],
  );
  assert.equal(nulRecords(new Uint8Array(0), "test").length, 0);
  assert.throws(() => nulRecords(new TextEncoder().encode("a\0\0b\0"), "test"), CustodyError);
});

test("parseStatusV2 handles ordinary, rename, untracked and ignored records", () => {
  const z = "\0";
  // Real Git shapes: `1` records carry two object names (the worktree hash is
  // omitted), `2` records carry two plus the rename score.
  const bytes = new TextEncoder().encode(
    `1 .M N... 100644 100644 100644 ${"a".repeat(40)} ${"b".repeat(40)} kept.txt${z}` +
      `2 RM N... 100644 100644 100644 ${"a".repeat(40)} ${"b".repeat(40)} R100 moved.txt${z}old.txt${z}` +
      `? fresh.txt${z}` +
      `! junk.log${z}`,
  );
  const parsed = parseStatusV2(bytes);
  assert.equal(parsed.changes.length, 2);
  assert.deepEqual(parsed.changes[0], {
    path: "kept.txt",
    originalPath: null,
    indexStatus: "unchanged",
    worktreeStatus: "modified",
  });
  assert.deepEqual(parsed.changes[1], {
    path: "moved.txt",
    originalPath: "old.txt",
    indexStatus: "renamed",
    worktreeStatus: "modified",
  });
  assert.deepEqual(parsed.untracked, ["fresh.txt"]);
  assert.deepEqual(parsed.ignored, ["junk.log"]);
});

test("parseForEachRef peels annotated tags and keeps lightweight targets", () => {
  const z = "\0";
  const annotated = `${"a".repeat(40)}`;
  const lightweight = `${"b".repeat(40)}`;
  const bytes = new TextEncoder().encode(
    `refs/tags/v1${z}${annotated}${z}tag${z}${lightweight}${z}\n` +
      `refs/heads/main${z}${lightweight}${z}commit${z}${z}\n`,
  );
  const refs = parseForEachRef(bytes, "sha1");
  assert.equal(refs[0]?.peeledOid, lightweight);
  assert.equal(refs[1]?.peeledOid, null);
});

test("parseLsFilesStage and parseLsTree record stages and gitlinks", () => {
  const z = "\0";
  const stage = new TextEncoder().encode(
    `100644 ${"a".repeat(40)} 0\tfile.txt${z}100644 ${"b".repeat(40)} 2\tconflict.txt${z}`,
  );
  const entries = parseLsFilesStage(stage, "sha1");
  assert.equal(entries[0]?.stage, 0);
  assert.equal(entries[1]?.stage, 2);
  const tree = new TextEncoder().encode(
    `100644 blob ${"a".repeat(40)}\tfile.txt${z}160000 commit ${"c".repeat(40)}\tsub${z}`,
  );
  const paths = parseLsTree(tree, "sha1");
  assert.equal(paths[0]?.mode, "100644");
  assert.equal(paths[1]?.mode, "160000");
  assert.throws(
    () => parseLsTree(new TextEncoder().encode(`040000 tree ${"a".repeat(40)}\tsub${z}`), "sha1"),
    CustodyError,
  );
});

test("parseReflogShow keeps selector provenance", () => {
  const z = "\0";
  const bytes = new TextEncoder().encode(`${"a".repeat(40)}${z}refs/heads/main@{1}${z}\n`);
  const entries = parseReflogShow(bytes, "sha1");
  assert.equal(entries[0]?.selector, "refs/heads/main@{1}");
});

test("parseFsck separates dangling candidates from corruption evidence", () => {
  const oid = "c".repeat(40);
  const report = parseFsck(
    new TextEncoder().encode(`dangling commit ${oid}\nunreachable commit ${oid}\n`),
    new TextEncoder().encode("missing blob 0000000000000000000000000000000000000000\n"),
    "sha1",
  );
  assert.equal(report.candidates.length, 1);
  assert.equal(report.candidates[0]?.oid, oid);
  assert.equal(report.corruption.length, 1);
});

test("strict decode helpers refuse malformed content", () => {
  assert.throws(() => strictUtf8(new Uint8Array([0xff, 0xfe]), "bad"), CustodyError);
  assert.throws(
    () => parseHashObjectLines(new TextEncoder().encode("a\n"), "sha1", 2),
    CustodyError,
  );
  assert.throws(() => parseCount(new TextEncoder().encode("12x\n")), CustodyError);
  assert.equal(parseBoolean(new TextEncoder().encode("true\n"), "flag"), true);
});

// ---------------------------------------------------------- integration

test("clean source with jj-colocated destination plans ready and touches nothing", async () => {
  const source = await fresh("clean-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await commit(source, "two", "README.md", "one\ntwo\n");
  await git(["tag", "-a", "v1", "-m", "annotated"], source);
  await git(["tag", "light"], source);
  const dest = await makeDest(source, "clean-dest");

  const before = {
    source: await fingerprintTree(source),
    sourceGit: await fingerprintTree(join(source, ".git")),
    dest: await fingerprintTree(dest),
    destGit: await fingerprintTree(join(dest, ".git")),
    destJj: await fingerprintTree(join(dest, ".jj")),
  };

  const result = await plan(input(source, dest));

  assert.deepEqual(codes(result), []);
  assert.equal(result.state, "ready");
  assert.equal(result.source.objectFormat, "sha1");
  assert.equal(result.source.head.symbolicRef, "refs/heads/main");
  assert.ok(result.source.fingerprints?.canonicalInputsSha256);
  assert.equal(result.source.jjCoverage.classification, "none");
  const kinds = new Set(result.pins.map(({ sourceKind }) => sourceKind));
  assert.ok(kinds.has("head"));
  assert.ok(kinds.has("branch"));
  assert.ok(kinds.has("tag"));
  const annotated = result.source.refs.find(({ name }) => name === "refs/tags/v1");
  const annotatedPin = result.pins.find(({ sourceName }) => sourceName === "refs/tags/v1");
  assert.equal(annotated?.objectType, "tag");
  assert.equal(annotatedPin?.objectType, "tag");
  assert.ok(result.baselines?.destinationPreRefsSha256);
  assert.equal(result.baselines?.selectedTipsNotInDestination, 0);

  assert.equal(await fingerprintTree(source), before.source);
  assert.equal(await fingerprintTree(join(source, ".git")), before.sourceGit);
  assert.equal(await fingerprintTree(dest), before.dest);
  assert.equal(await fingerprintTree(join(dest, ".git")), before.destGit);
  assert.equal(await fingerprintTree(join(dest, ".jj")), before.destJj);
});

test("detached divergent HEAD counts exactly against the recorded baseline", async () => {
  const source = await fresh("detached-src");
  await initRepo(source);
  const base = await commit(source, "base", "README.md", "base\n");
  await git(["remote", "add", "github", "file:///nowhere/github"], source);
  await git(["update-ref", "refs/remotes/github/main", base], source);
  await commit(source, "one", "README.md", "base\none\n");
  await commit(source, "two", "README.md", "base\none\ntwo\n");
  await commit(source, "three", "README.md", "base\none\ntwo\nthree\n");
  await git(["checkout", "--quiet", "--detach"], source);
  const dest = await makeDest(source, "detached-dest");

  const result = await plan(input(source, dest));
  assert.equal(result.state, "ready");
  assert.equal(result.source.head.symbolicRef, null);
  assert.equal(result.baselines?.headNotInRecordedBaseline, 3);
  assert.deepEqual(
    result.baselines?.sourceRemoteTracking.map(({ remote, freshness }) => ({ remote, freshness })),
    [{ remote: "github", freshness: "local-only" }],
  );
  assert.ok(result.warnings.some(({ code }) => code === "detached-head"));
});

test("dirty worktree carries an exact snapshot proposal, not a fabricated snapshot", async () => {
  const source = await fresh("dirty-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await commit(source, "keys", ".env", "SECRET_TOKEN=wildebeest\n");
  await git(["tag", "-a", "v1", "-m", "v1"], source);
  await writeFileUtf8(join(source, "README.md"), "one\ndirty\n");
  await writeFileUtf8(join(source, ".env"), "SECRET_TOKEN=wildebeest\nrotated\n");
  await writeFileUtf8(join(source, "untracked.txt"), "new\n");
  await writeFileUtf8(join(source, "debug.log"), "noise\n");
  await writeFileUtf8(join(source, ".gitignore"), "debug.log\n");
  // Fingerprints are taken after the dirty state exists: the plan and its
  // private-scratch preview must not disturb the source, ODB included.
  const beforeWorktree = await fingerprintTree(source);
  const beforeGit = await fingerprintTree(join(source, ".git"));
  const dest = await makeDest(source, "dirty-dest");

  const result = await plan(input(source, dest));
  assert.equal(result.state, "blocked");
  assert.ok(codes(result).includes("path-review-required"));
  assert.ok(!codes(result).includes("snapshot-apply-pending"));
  assert.ok(result.source.untrackedPaths?.some((path) => path === "untracked.txt"));
  assert.ok(result.source.ignoredPaths?.some((path) => path === "debug.log"));
  assert.ok(result.source.trackedSensitivePaths?.some(({ subject }) => subject === ".env"));
  assert.ok(result.source.worktreeChanges?.some(({ path }) => path === "README.md"));
  assert.ok(
    result.source.leftBehind?.some(
      ({ code, subject }) => code === "ignored-runtime-state" && subject === "debug.log",
    ),
  );
  assert.ok(result.retirementUnresolved.some(({ code }) => code === "publication-review"));
  // The proposal is the exact preview: synthetic tree, deterministic commit,
  // manifest digest an operator can bind a review against.
  const proposal = result.proposedSnapshot;
  assert.ok(proposal !== null, "blocked dirty plan carries the preview proposal");
  assert.ok(proposal.paths.some(({ path }) => path === "untracked.txt"));
  assert.ok(proposal.paths.some(({ path }) => path === "README.md"));
  assert.ok(!proposal.paths.some(({ path }) => path === "debug.log"));
  assert.match(proposal.commitOid, /^[0-9a-f]{40}$/);
  assert.match(proposal.manifestSha256, /^[0-9a-f]{64}$/);
  assert.deepEqual(proposal.reviewRequirements.sensitivePaths, [".env"]);
  assert.equal(result.pins, null);
  // Privacy: the secret value never appears in the serialized plan.
  assert.ok(!JSON.stringify(result).includes("wildebeest"));
  // Read-only proof: worktree and .git (ODB included) are byte-identical.
  assert.equal(await fingerprintTree(source), beforeWorktree);
  assert.equal(await fingerprintTree(join(source, ".git")), beforeGit);
});

test("snapshot review bound to the preview manifest clears the review blocker", async () => {
  const source = await fresh("review-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await commit(source, "keys", ".env", "SECRET_TOKEN=otter\n");
  await writeFileUtf8(join(source, ".env"), "SECRET_TOKEN=otter\nchanged\n");
  const dest = await makeDest(source, "review-dest");

  const unreviewed = await plan(input(source, dest));
  assert.equal(unreviewed.state, "blocked");
  assert.ok(codes(unreviewed).includes("path-review-required"));
  const proposal = unreviewed.proposedSnapshot;
  assert.ok(proposal !== null);

  const envEntry = proposal.paths.find(({ path }) => path === ".env");
  assert.ok(envEntry !== undefined);
  const reviewFile = join(ROOT, "review.json");
  await writeFileUtf8(
    reviewFile,
    JSON.stringify({
      schema: "compfuzor.archive-path-review/v1",
      manifestSha256: proposal.manifestSha256,
      included: [
        {
          path: envEntry.path,
          mode: envEntry.mode,
          blobOid: envEntry.blobOid,
          classification: "credential",
          decision: "local-custody-approved",
          reason: "fixture approval",
        },
      ],
      stagedVsUnstaged: null,
    }),
  );
  const reviewed = await plan(input(source, dest, { pathReview: reviewFile }));
  assert.deepEqual(codes(reviewed), []);
  assert.equal(reviewed.state, "ready");
  // The approved snapshot is the proposal without proposal-only fields,
  // carrying the validated review; a working-copy pin covers its commit.
  assert.ok(reviewed.proposedSnapshot !== null);
  assert.ok(!("manifestSha256" in reviewed.proposedSnapshot));
  assert.ok(!("reviewRequirements" in reviewed.proposedSnapshot));
  assert.equal(reviewed.proposedSnapshot.commitOid, proposal.commitOid);
  assert.equal(reviewed.proposedSnapshot.pathReview?.manifestSha256, proposal.manifestSha256);
  const wcPin = reviewed.pins.find(({ sourceKind }) => sourceKind === "working-copy");
  assert.ok(wcPin !== undefined);
  assert.equal(wcPin.sourceOid, proposal.commitOid);
  assert.ok(wcPin.destinationRef.includes("/working-copy/"));
  assert.equal(reviewed.cleanHeadPathReview, null);
  assert.ok(!JSON.stringify(reviewed).includes("otter"));

  // A stale review (wrong manifest digest) stays blocked with the visible
  // proposal so the operator can rebind against the reported digest.
  const staleFile = join(ROOT, "review-stale.json");
  await writeFileUtf8(
    staleFile,
    JSON.stringify({
      schema: "compfuzor.archive-path-review/v1",
      manifestSha256: "0".repeat(64),
      included: [],
      stagedVsUnstaged: null,
    }),
  );
  const stale = await plan(input(source, dest, { pathReview: staleFile }));
  assert.equal(stale.state, "blocked");
  assert.ok(codes(stale).includes("path-review-invalid"));
  assert.ok(stale.proposedSnapshot !== null);
});

test("plain dirty worktree without sensitive paths plans ready with a reviewless snapshot", async () => {
  const source = await fresh("plain-dirty-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await commit(source, "two", "notes.txt", "plain\n");
  await writeFileUtf8(join(source, "notes.txt"), "plain\nedited\n");
  await writeFileUtf8(join(source, "extra.txt"), "brand new\n");
  const dest = await makeDest(source, "plain-dirty-dest");

  const result = await plan(input(source, dest));
  assert.deepEqual(codes(result), []);
  assert.equal(result.state, "ready");
  assert.ok(result.proposedSnapshot !== null);
  assert.equal(result.proposedSnapshot.pathReview, null);
  assert.ok(result.proposedSnapshot.paths.some(({ path }) => path === "extra.txt"));
  assert.ok(result.pins.some(({ sourceKind }) => sourceKind === "working-copy"));
  assert.equal(result.proposedSnapshot.stagedVsUnstaged, "none");
});

test("tracked LFS pointer without filter configuration is a named blocker", async () => {
  const source = await fresh("lfs-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  const pointer =
    "version https://git-lfs.github.com/spec/v1\noid sha256:4355a46b19d348dc2f57c046f8ef63d4538ebb936000f6c10d7823b49e72009c\nsize 7\n";
  await writeFileUtf8(join(source, "asset.bin"), pointer);
  await git(["add", "-f", "asset.bin"], source);
  await git(["commit", "--quiet", "-m", "pointer"], source);
  const dest = await makeDest(source, "lfs-dest");

  const result = await plan(input(source, dest));
  assert.equal(result.state, "blocked");
  assert.ok(codes(result).includes("source-lfs-pointer"), codes(result).join(","));
  // The pointer payload (its oid line) is never emitted in the plan.
  assert.ok(!JSON.stringify(result).includes("4355a46b19d348dc2f57c046f8ef63d4538ebb93"));

  // HEAD/index pointers remain relevant when a worktree edit hides the header.
  await writeFileUtf8(join(source, "asset.bin"), "new local payload\n");
  const edited = await plan(input(source, dest));
  assert.equal(edited.state, "blocked");
  assert.ok(codes(edited).includes("source-lfs-pointer"));
  assert.ok(!JSON.stringify(edited).includes("4355a46b19d348dc2f57c046f8ef63d4538ebb93"));
});

test("unborn HEAD reports a blocker and a null head category", async () => {
  const source = await fresh("unborn-src");
  await initRepo(source, "feature");
  const result = await plan(input(source, join(ROOT, "no-dest")));
  assert.equal(result.state, "blocked");
  assert.ok(codes(result).includes("source-unborn-head"));
  assert.ok(codes(result).includes("destination-missing"));
  assert.equal(result.source.head, null);
  assert.deepEqual(result.source.refs, []);
});

test("non-UTF-8 untracked paths block with a named code, not a failed command", async () => {
  const source = await fresh("bytes-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  const bad = Buffer.from([0x69, 0x6e, 0x76, 0xff, 0x69, 0x6c, 0x64, 0x2e, 0x74, 0x78, 0x74]);
  await writeFile(Buffer.concat([Buffer.from(`${source}/`), bad]), "junk");
  const dest = await makeDest(source, "bytes-dest");
  const result = await plan(input(source, dest));
  assert.equal(result.state, "blocked");
  assert.ok(codes(result).includes("source-untracked-unrepresentable"));
  assert.equal(result.source.untrackedPaths, null);
});

test("unsupported Git variants are named blockers", async () => {
  const dest = join(ROOT, "never");
  const variants: readonly [string, string, () => Promise<PlanV1>][] = [
    [
      "alternates",
      "source-alternates",
      async () => {
        const source = await fresh("alt-src");
        await initRepo(source);
        await commit(source, "one", "README.md", "one\n");
        await mkdir(join(source, ".git/objects/info"), { recursive: true });
        await writeFileUtf8(join(source, ".git/objects/info/alternates"), "/somewhere/else\n");
        return plan(input(source, dest));
      },
    ],
    [
      "shallow",
      "source-shallow",
      async () => {
        const source = await fresh("shallow-src");
        await initRepo(source);
        const head = await commit(source, "one", "README.md", "one\n");
        await writeFileUtf8(join(source, ".git/shallow"), head);
        return plan(input(source, dest));
      },
    ],
    [
      "promisor",
      "source-partial-clone",
      async () => {
        const source = await fresh("promisor-src");
        await initRepo(source);
        await commit(source, "one", "README.md", "one\n");
        await git(["config", "remote.origin.promisor", "true"], source);
        await git(["config", "remote.origin.partialclonefilter", "blob:none"], source);
        return plan(input(source, dest));
      },
    ],
    [
      "sparse",
      "source-sparse-checkout",
      async () => {
        const source = await fresh("sparse-src");
        await initRepo(source);
        await commit(source, "one", "README.md", "one\n");
        await git(["config", "core.sparseCheckout", "true"], source);
        return plan(input(source, dest));
      },
    ],
    [
      "filter",
      "source-filter-configured",
      async () => {
        const source = await fresh("filter-src");
        await initRepo(source);
        await commit(source, "one", "README.md", "one\n");
        await git(["config", "filter.lfs.clean", "git-lfs clean -- %f"], source);
        await git(["config", "filter.lfs.smudge", "git-lfs smudge -- %f"], source);
        return plan(input(source, dest));
      },
    ],
    [
      "bare",
      "source-bare",
      async () => {
        const source = await fresh("bare-src");
        await git(["init", "--quiet", "--bare", "."], source);
        return plan(input(source, dest));
      },
    ],
    [
      "reftable",
      "source-unsupported-extension",
      async () => {
        const source = await fresh("reft-src");
        await git(["init", "--quiet", "--ref-format=reftable", "-b", "main", "."], source);
        await git(["config", "user.email", "c@e.invalid"], source);
        await git(["config", "user.name", "c"], source);
        await commit(source, "one", "README.md", "one\n");
        return plan(input(source, dest));
      },
    ],
    [
      "linked worktree",
      "source-gitfile-linked-worktree",
      async () => {
        const main = await fresh("wt-main");
        await initRepo(main);
        await commit(main, "one", "README.md", "one\n");
        const worktree = join(ROOT, "wt-linked");
        await rm(worktree, { recursive: true, force: true });
        await git(["worktree", "add", "--quiet", "--detach", worktree], main);
        return plan(input(worktree, dest));
      },
    ],
    [
      "gitlink",
      "source-submodule-gitlink",
      async () => {
        const source = await fresh("submodule-src");
        await initRepo(source);
        const head = await commit(source, "one", "README.md", "one\n");
        await git(["update-index", "--add", "--cacheinfo", `160000,${head},vendored`], source);
        return plan(input(source, dest));
      },
    ],
  ];
  for (const [name, code, run] of variants) {
    const result = await run();
    assert.equal(result.state, "blocked", `${name}: expected blocked plan`);
    assert.ok(
      codes(result).includes(code),
      `${name}: expected ${code} in [${codes(result).join(",")}]`,
    );
  }
});

test("stash and dangling work blocks until dispositioned, then plans", async () => {
  const source = await fresh("stash-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await writeFileUtf8(join(source, "s1.txt"), "one\n");
  await git(["add", "s1.txt"], source);
  await git(["stash", "--quiet"], source);
  await writeFileUtf8(join(source, "s2.txt"), "two\n");
  await git(["add", "s2.txt"], source);
  await git(["stash", "--quiet"], source);
  const dropped = await commit(source, "doomed", "README.md", "one\ndoomed\n");
  await git(["reset", "--quiet", "--hard", "HEAD~1"], source);
  const dest = await makeDest(source, "stash-dest");

  const blocked = await plan(input(source, dest));
  assert.equal(blocked.state, "blocked");
  assert.ok(codes(blocked).includes("candidates-unclassified"));
  const stashOlder = blocked.source.candidates?.filter(({ kind }) => kind === "stash-older") ?? [];
  assert.equal(stashOlder.length, 1);
  assert.equal(stashOlder[0]?.disposition, "pin");
  const droppedCandidate = blocked.source.candidates?.find(({ oid }) => oid === dropped);
  assert.ok(droppedCandidate !== undefined);
  assert.equal(droppedCandidate.disposition, "unclassified");
  assert.ok(droppedCandidate.provenance.includes("fsck --no-reflogs --unreachable"));

  const dispositions = join(ROOT, "dispositions.json");
  // Disposition every unclassified candidate: the reset-away commit plus any
  // commits only reachable through older stash entries.
  const unclassifiedAll = (blocked.source.candidates ?? []).filter(
    ({ disposition }) => disposition === "unclassified",
  );
  assert.ok(unclassifiedAll.length >= 1);
  const decisions: Record<string, { disposition: "pin" }> = {};
  for (const candidate of unclassifiedAll)
    decisions[`${candidate.kind}:${candidate.oid}`] = { disposition: "pin" };
  await writeFileUtf8(dispositions, JSON.stringify(decisions));
  const ready = await plan(input(source, dest, { dispositions }));
  assert.deepEqual(codes(ready), []);
  assert.equal(ready.state, "ready");
  assert.ok(ready.source.candidates?.some(({ disposition }) => disposition === "pin"));
  for (const candidate of unclassifiedAll)
    assert.ok(
      ready.pins.some(({ sourceName }) => sourceName === `${candidate.kind}:${candidate.oid}`),
    );
  assert.equal(
    ready.source.dispositionsFileSha256,
    createHash("sha256")
      .update(await readFile(dispositions))
      .digest("hex"),
  );
});

test("clean sensitive HEAD requires and accepts an exact review via headManifestSha256", async () => {
  const source = await fresh("clean-review-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await commit(source, "keys", "deploy.env", "TOKEN=heron\n");
  const dest = await makeDest(source, "clean-review-dest");

  const unreviewed = await plan(input(source, dest));
  assert.equal(unreviewed.state, "blocked");
  assert.ok(codes(unreviewed).includes("clean-head-path-review-required"));
  assert.ok(unreviewed.headManifestSha256);
  assert.equal(unreviewed.proposedSnapshot, null);

  const envEntry = unreviewed.source.head?.treePaths.find(({ path }) => path === "deploy.env");
  assert.ok(envEntry !== undefined);
  const reviewFile = join(ROOT, "clean-review.json");
  await writeFileUtf8(
    reviewFile,
    JSON.stringify({
      schema: "compfuzor.archive-path-review/v1",
      manifestSha256: unreviewed.headManifestSha256,
      included: [
        {
          path: envEntry.path,
          mode: envEntry.mode,
          blobOid: envEntry.blobOid,
          classification: "credential",
          decision: "local-custody-approved",
          reason: "fixture approval",
        },
      ],
      stagedVsUnstaged: null,
    }),
  );
  const reviewed = await plan(input(source, dest, { pathReview: reviewFile }));
  assert.deepEqual(codes(reviewed), []);
  assert.equal(reviewed.state, "ready");
  assert.ok(reviewed.cleanHeadPathReview !== null);
  assert.equal(reviewed.proposedSnapshot, null);
  assert.ok(!JSON.stringify(reviewed).includes("heron"));
});

test("jj-colocated clean source is git-covered and stays byte-identical", async () => {
  const source = await fresh("jj-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await sh("jj", ["git", "init", "--colocate", "--quiet"], source);
  const dest = await makeDest(source, "jj-dest");
  const before = {
    jj: await fingerprintTree(join(source, ".jj")),
    gitDir: await fingerprintTree(join(source, ".git")),
    worktree: await fingerprintTree(source),
  };

  const result = await plan(input(source, dest));
  assert.deepEqual(codes(result), []);
  assert.equal(result.state, "ready");
  assert.equal(result.source.jjCoverage.classification, "git-covered");
  assert.ok(result.source.jjCoverage.operationId);
  assert.ok(result.source.fingerprints?.jjStoreSha256);
  assert.ok(result.retirementUnresolved.some(({ code }) => code === "jj-operation-history"));

  assert.equal(await fingerprintTree(join(source, ".jj")), before.jj);
  assert.equal(await fingerprintTree(join(source, ".git")), before.gitDir);
  assert.equal(await fingerprintTree(source), before.worktree);
});

test("jj-only commit blocks coverage", async () => {
  const source = await fresh("jjonly-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await sh("jj", ["git", "init", "--colocate", "--quiet"], source);
  await sh("jj", ["new", "-m", "jj-only work"], source);
  const dest = await makeDest(source, "jjonly-dest");
  const before = await fingerprintTree(join(source, ".jj"));

  const result = await plan(input(source, dest));
  assert.equal(result.state, "blocked");
  assert.ok(codes(result).includes("jj-heads-uncovered"), codes(result).join(","));
  assert.equal(result.source.jjCoverage?.classification, "blocked");
  assert.equal(await fingerprintTree(join(source, ".jj")), before);
});

test("inert .jj placeholder is an inspection failure, not absence", async () => {
  const source = await fresh("placeholder-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await mkdir(join(source, ".jj"));
  const dest = await makeDest(source, "placeholder-dest");
  const result = await plan(input(source, dest));
  assert.equal(result.state, "blocked");
  assert.ok(codes(result).includes("jj-inspection-failed"), codes(result).join(","));
  assert.equal(result.source.jjCoverage?.classification, "blocked");
});

test("missing, dirty and mismatched destinations block", async () => {
  const source = await fresh("dest-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");

  const missing = await plan(input(source, join(ROOT, "absent")));
  assert.equal(missing.state, "blocked");
  assert.ok(codes(missing).includes("destination-missing"));
  assert.equal(missing.baselines, null);

  const dirty = await makeDest(source, "dirty-dest2");
  await writeFileUtf8(join(dirty, "README.md"), "mutated\n");
  const dirtyPlan = await plan(input(source, dirty));
  assert.ok(codes(dirtyPlan).includes("destination-worktree-dirty"));

  const mismatch = await makeDest(source, "mismatch-dest");
  const mismatchPlan = await plan(input(source, mismatch, { repo: "https://elsewhere/x" }));
  assert.ok(codes(mismatchPlan).includes("destination-remote-mismatch"));
});

test("nested or aliased paths are rejected as invalid input", async () => {
  const source = await fresh("nested-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  await assert.rejects(plan(input(source, join(source, "inside"))), CustodyError);
  await assert.rejects(plan(input(source, source)), CustodyError);
  const alias = join(ROOT, "source-alias");
  await rm(alias, { force: true });
  await symlink(source, alias);
  const before = await fingerprintTree(join(source, ".git/objects"));
  await assert.rejects(plan(input(source, alias)), CustodyError);
  await assert.rejects(Effect.runPromise(applyAdoption(input(source, alias))), CustodyError);
  assert.equal(await fingerprintTree(join(source, ".git/objects")), before);
  await assert.rejects(plan(input(source, join(alias, "nested"))), CustodyError);
});

test("dispositions referencing unknown candidates are rejected", async () => {
  const source = await fresh("unknown-disp-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  const dest = await makeDest(source, "unknown-disp-dest");
  const dispositions = join(ROOT, "unknown.json");
  await writeFileUtf8(
    dispositions,
    JSON.stringify({ [`reflog:${"0".repeat(40)}`]: { disposition: "pin" } }),
  );
  await assert.rejects(plan(input(source, dest, { dispositions })), CustodyError);
});

test("deterministic canonical input hash across repeated plans", async () => {
  const source = await fresh("stable-src");
  await initRepo(source);
  await commit(source, "one", "README.md", "one\n");
  const dest = await makeDest(source, "stable-dest");
  const first = await plan(input(source, dest));
  const second = await plan(input(source, dest));
  assert.equal(first.state, "ready");
  assert.equal(
    first.source.fingerprints?.canonicalInputsSha256,
    second.source.fingerprints?.canonicalInputsSha256,
  );
});
