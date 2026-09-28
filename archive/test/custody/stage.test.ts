import assert from "node:assert/strict";
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  readlink,
  rename,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { join } from "node:path";
import { test } from "node:test";
import { Effect } from "effect";
import {
  candidateIdentity,
  canonicalJson,
  parsePathReview,
  pinRef,
  repoPath,
  sha256,
} from "../../src/custody/codec.ts";
import { CustodyError } from "../../src/custody/errors.ts";
import type { Oid, PathEntry, PinIntent, RepoPath } from "../../src/custody/model.ts";
import {
  prepareSnapshot,
  previewSnapshot,
  proveBundle,
  WORKTREE_V1_METADATA,
} from "../../src/custody/stage.ts";
import type { StageHandle } from "../../src/custody/stage.ts";
import { git, gitChecked, utf8Fatal } from "../../src/repository/git.ts";

// Every fixture is disposable scratch under .test-agent; production
// repositories are never touched. All staging runs the real installed git
// through the shared Effect adapter.
const scratchRoot = join(import.meta.dirname, "..", "..", "..", ".test-agent", "custody-stage");
const identity = [
  "-c",
  "user.name=custody",
  "-c",
  "user.email=custody@example.invalid",
  "-c",
  "commit.gpgsign=false",
] as const;

const run = async (cwd: string, ...args: string[]): Promise<string> =>
  utf8Fatal(await Effect.runPromise(gitChecked(args, { cwd }))).trim();

/** Fingerprint lines: `path sha256` for files, `path -> target` for symlinks. */
async function treeLines(root: string, skip: string | null): Promise<string[]> {
  const lines: string[] = [];
  const walk = async (dir: string, prefix: string): Promise<void> => {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      if (entry.name === skip) continue;
      const abs = join(dir, entry.name);
      const rel = prefix + entry.name;
      if (entry.isDirectory()) await walk(abs, `${rel}/`);
      else if (entry.isSymbolicLink()) lines.push(`${rel} -> ${await readlink(abs)}`);
      else lines.push(`${rel} ${sha256(await readFile(abs))}`);
    }
  };
  await walk(root, "");
  return lines.sort();
}

const fingerprintsOf = async (sourceRoot: string): Promise<Record<string, string>> => {
  const gitDir = join(sourceRoot, ".git");
  return {
    worktree: sha256(Buffer.from((await treeLines(sourceRoot, ".git")).join("\n"))),
    odb: sha256(Buffer.from((await treeLines(join(gitDir, "objects"), null)).join("\n"))),
    refs: sha256(Buffer.from((await treeLines(join(gitDir, "refs"), null)).join("\n"))),
    reflogs: sha256(Buffer.from((await treeLines(join(gitDir, "logs"), null)).join("\n"))),
    index: sha256(await readFile(join(gitDir, "index"))),
  };
};

type Area = { root: string; source: string };

async function area(
  t: { after: (hook: () => Promise<unknown>) => void },
  name: string,
): Promise<Area> {
  await mkdir(scratchRoot, { recursive: true });
  const root = await mkdtemp(join(scratchRoot, `${name}-`));
  t.after(async () => {
    await rm(root, { recursive: true, force: true });
  });
  const source = join(root, "source");
  await mkdir(source);
  return { root, source };
}

interface Legacy {
  readonly source: string;
  readonly head: string;
  readonly headTree: string;
  readonly branchRef: string;
  readonly annotatedTagOid: string;
  readonly stashTipOid: string;
  readonly olderStashOid: string;
  readonly secretKey: RepoPath;
}

/** Dirty legacy checkout: tracked edit + deletion, binary, symlinks, weird
 * names, an ignored runtime file, a staged index change, annotated and
 * lightweight tags, a branch, and a two-entry stash. */
async function dirtyLegacy(
  t: { after: (hook: () => Promise<unknown>) => void },
  name: string,
  format = "sha1",
): Promise<Legacy & Area> {
  const home = await area(t, name);
  const { source } = home;
  await run(
    source,
    "init",
    "--quiet",
    ...(format === "sha256" ? ["--object-format=sha256"] : []),
    source,
  );
  await run(source, ...identity, "commit", "--quiet", "--allow-empty", "-m", "base");
  await writeFile(join(source, "tracked.txt"), "hello\n");
  await writeFile(
    join(source, "bin.dat"),
    Uint8Array.from([0x00, 0xff, 0x00, 0x62, 0x00, 0x80, 0x00]),
  );
  await symlink("tracked.txt", join(source, "rel-link"));
  await writeFile(join(source, "secret.key"), "hunter2\n");
  await writeFile(join(source, ".gitignore"), "*.ignored\n");
  await run(source, ...identity, "add", "-A", ".");
  await run(source, ...identity, "commit", "--quiet", "-m", "files");
  const head = await run(source, "rev-parse", "HEAD");
  await run(source, "branch", "topic");
  await run(source, ...identity, "tag", "-a", "v1", "-m", "annotated");
  const annotatedTagOid = await run(source, "rev-parse", "v1");
  await run(source, "tag", "lw");

  // Dirty worktree: modification, deletion, ignored runtime state, and the
  // selected untracked set (plain, glob-like name, symlink). The index is
  // left clean here; a staged split is added explicitly by the review test.
  await writeFile(join(source, "tracked.txt"), "changed\n");
  const olderStashOid = await run(source, ...identity, "stash", "create");
  await run(source, "stash", "store", "-m", "older", olderStashOid);
  await writeFile(join(source, "tracked.txt"), "changed-again\n");
  const stashTipOid = await run(source, ...identity, "stash", "create");
  await run(source, "stash", "store", "-m", "current", stashTipOid);
  await rm(join(source, "bin.dat"));
  await writeFile(join(source, "untracked.txt"), "untracked\n");
  await writeFile(join(source, "we*ird [na]mé.txt"), "weird name");
  await symlink("/etc/hostname", join(source, "abs-link"));
  await writeFile(join(source, "runtime.ignored"), "db\n");
  await writeFile(join(source, "staged-only.txt"), "staged\n");
  return {
    ...home,
    head,
    headTree: await run(source, "rev-parse", `${head}^{tree}`),
    branchRef: `refs/heads/${await run(source, "symbolic-ref", "--short", "HEAD")}`,
    annotatedTagOid,
    stashTipOid,
    olderStashOid,
    secretKey: repoPath("secret.key"),
  };
}

interface SnapshotRequest {
  readonly source: string;
  readonly head: string;
  readonly scratchRoot: string;
  readonly expected?: readonly PathEntry[] | null;
  readonly sensitive?: readonly RepoPath[];
  readonly review?: ReturnType<typeof parsePathReview>;
  readonly restage?: readonly RepoPath[];
  readonly untracked?: readonly RepoPath[];
  readonly stagedVsUnstaged?: "none" | "reported-not-preserved";
}

const restageDefaults = (): readonly RepoPath[] => [repoPath("tracked.txt"), repoPath("bin.dat")];
const untrackedDefaults = (): readonly RepoPath[] => [
  repoPath("untracked.txt"),
  repoPath("we*ird [na]mé.txt"),
  repoPath("abs-link"),
  repoPath("staged-only.txt"),
];

const snapshotInput = (ask: SnapshotRequest) => ({
  sourceRoot: ask.source,
  scratchRoot: ask.scratchRoot,
  objectFormat: "sha1" as const,
  headOid: ask.head as Oid,
  restageTracked: ask.restage ?? restageDefaults(),
  addUntracked: ask.untracked ?? untrackedDefaults(),
  stagedVsUnstaged: ask.stagedVsUnstaged ?? "none",
  excludeFileSha256: null,
  excludedUntracked: [],
  ignoredPaths: [repoPath("runtime.ignored")],
  trackedSensitivePaths: ask.sensitive ?? [],
  pathReview: ask.review ?? null,
  expected: ask.expected ?? null,
});

const request = (ask: SnapshotRequest) => prepareSnapshot(snapshotInput(ask));

const custodyError = async (promise: Promise<unknown>): Promise<CustodyError> => {
  try {
    await promise;
  } catch (error) {
    assert.ok(error instanceof CustodyError, `expected CustodyError, got ${String(error)}`);
    return error;
  }
  return assert.fail("expected the call to fail");
};

test("prepareSnapshot stages binaries, untracked files, symlinks and deletions into a private ODB, never the source", async (t) => {
  const legacy = await dirtyLegacy(t, "stage-dirty");
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  const before = await fingerprintsOf(legacy.source);

  const stage = await request({ source: legacy.source, head: legacy.head, scratchRoot: scratch });
  assert.ok(stage.snapshot, "a dirty tree must produce a snapshot");
  const paths = new Map(stage.snapshot.paths.map((entry) => [entry.path as string, entry]));
  assert.equal(stage.snapshot.parentOid, legacy.head);
  assert.notEqual(stage.snapshot.treeOid, stage.headTreeOid);
  assert.ok(stage.snapshotCommitOid);
  // Deletion staged, modification staged, untracked added, symlinks stay links.
  assert.equal(paths.has("bin.dat"), false, "deleted tracked file must leave the tree");
  const stagedTracked = utf8Fatal(
    (
      await Effect.runPromise(
        git(["cat-file", "blob", paths.get("tracked.txt")?.blobOid ?? ""], {
          cwd: stage.gitDir,
          env: { GIT_DIR: stage.gitDir, GIT_OBJECT_DIRECTORY: join(stage.gitDir, "objects") },
        }),
      )
    ).stdout,
  );
  assert.equal(stagedTracked, "changed-again\n");
  assert.equal(paths.get("untracked.txt")?.mode, "100644");
  assert.equal(paths.get("we*ird [na]mé.txt")?.mode, "100644");
  assert.equal(paths.get("staged-only.txt")?.mode, "100644");
  assert.equal(paths.get("abs-link")?.mode, "120000");
  assert.equal(paths.get("rel-link")?.mode, "120000");
  assert.equal(paths.get("secret.key")?.mode, "100644");
  assert.ok(paths.has(".gitignore"), "unchanged tracked files remain in the tree");
  assert.equal(paths.has("runtime.ignored"), false, "ignored runtime state is left behind");
  // Manifest is sorted by path.
  const order = stage.snapshot.paths.map(({ path }) => path as string);
  assert.deepEqual(order, [...order].sort());

  // A blob the source never hashed (stash create only hashed tracked files)
  // exists in the private ODB and NOT in the source.
  const freshBlob = paths.get("untracked.txt")?.blobOid as string;
  const stageObject = await Effect.runPromise(
    git(["cat-file", "-e", freshBlob], {
      cwd: stage.gitDir,
      env: { GIT_DIR: stage.gitDir, GIT_OBJECT_DIRECTORY: join(stage.gitDir, "objects") },
    }),
  );
  assert.equal(stageObject.exitCode, 0);
  const sourceObject = await Effect.runPromise(
    git(["cat-file", "-e", freshBlob], { cwd: legacy.source }),
  );
  assert.notEqual(sourceObject.exitCode, 0);

  assert.deepEqual(
    await fingerprintsOf(legacy.source),
    before,
    "source ODB/index/refs/reflogs/worktree must be unchanged",
  );
});

test("redirecting GIT_INDEX_FILE alone still leaks blobs into the source ODB (positive control)", async (t) => {
  const home = await area(t, "temp-index-control");
  await run(home.source, "init", "--quiet");
  await run(home.source, ...identity, "commit", "--quiet", "--allow-empty", "-m", "base");
  await writeFile(join(home.source, "leak.txt"), "leak-content\n");
  const before = await fingerprintsOf(home.source);
  const expectedOid = utf8Fatal(
    (
      await Effect.runPromise(
        git(["hash-object", "--stdin"], {
          cwd: home.source,
          input: new TextEncoder().encode("leak-content\n"),
        }),
      )
    ).stdout,
  ).trim();

  // The hazardous historical pattern: only the index is redirected. This is
  // exactly what prepareSnapshot must never do; this control proves the
  // fixture fingerprints below can detect the leak class.
  const leaked = await Effect.runPromise(
    git(["add", "leak.txt"], {
      cwd: home.source,
      env: { GIT_INDEX_FILE: join(home.root, "temp-index") },
    }),
  );
  assert.equal(leaked.exitCode, 0);

  const after = await fingerprintsOf(home.source);
  assert.notEqual(after.odb, before.odb, "the untracked blob must land in the source ODB");
  assert.equal(after.index, before.index, "the source index itself stays untouched");
  assert.equal(after.worktree, before.worktree);
  const present = await Effect.runPromise(
    git(["cat-file", "-e", expectedOid], { cwd: home.source }),
  );
  assert.equal(present.exitCode, 0, "the leaked object is the payload blob");
});

test("deterministic metadata: identical input restages to the identical commit OID", async (t) => {
  const legacy = await dirtyLegacy(t, "determinism");
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  const first = await request({ source: legacy.source, head: legacy.head, scratchRoot: scratch });
  const before = await fingerprintsOf(legacy.source);
  const second = await request({ source: legacy.source, head: legacy.head, scratchRoot: scratch });
  assert.ok(first.snapshot && second.snapshot);
  assert.equal(second.snapshot.commitOid, first.snapshot.commitOid);
  assert.equal(second.snapshot.treeOid, first.snapshot.treeOid);
  assert.deepEqual(second.snapshot.paths, first.snapshot.paths);
  assert.deepEqual(await fingerprintsOf(legacy.source), before);
  // Fixed metadata is observable in the commit itself.
  const commit = utf8Fatal(
    (
      await Effect.runPromise(
        git(["cat-file", "commit", first.snapshot.commitOid], { cwd: first.gitDir }),
      )
    ).stdout,
  );
  assert.match(
    commit,
    new RegExp(`author ${WORKTREE_V1_METADATA.authorName} <${WORKTREE_V1_METADATA.authorEmail}>`),
  );
  assert.match(commit, / 0 \+0000/);
  assert.match(commit, /compfuzor worktree snapshot \(worktree-v1\)/);
});

test("clean source produces no snapshot; unchanged restage is not a difference", async (t) => {
  const legacy = await dirtyLegacy(t, "clean");
  // Reset the dirty state: restore deleted file, drop new paths, reset index.
  await run(legacy.source, "stash", "clear");
  await run(legacy.source, "reset", "--hard", "HEAD");
  await rm(join(legacy.source, "untracked.txt"));
  await rm(join(legacy.source, "we*ird [na]mé.txt"));
  await rm(join(legacy.source, "abs-link"));
  await rm(join(legacy.source, "runtime.ignored"));
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  const clean = await request({
    source: legacy.source,
    head: legacy.head,
    scratchRoot: scratch,
    restage: [repoPath("tracked.txt")],
    untracked: [],
    sensitive: [],
  });
  assert.equal(clean.snapshot, null);
  assert.equal(clean.snapshotCommitOid, null);
  assert.equal(clean.headTreeOid, await run(legacy.source, "rev-parse", `${legacy.head}^{tree}`));
  // Clean preview is null (the plan's proposedSnapshot shape); sensitive
  // review of a clean HEAD tree is the receipt's cleanHeadPathReview, not
  // this module's business. The preview's scratch is disposed either way.
  const cleanPreview = await previewSnapshot(
    snapshotInput({
      source: legacy.source,
      head: legacy.head,
      scratchRoot: scratch,
      restage: [repoPath("tracked.txt")],
      untracked: [],
      sensitive: [repoPath("secret.key")],
    }),
  );
  assert.equal(cleanPreview, null);
  const previewScratch = join(legacy.root, "preview-scratch");
  await mkdir(previewScratch);
  assert.equal(
    await previewSnapshot(
      snapshotInput({
        source: legacy.source,
        head: legacy.head,
        scratchRoot: previewScratch,
        restage: [repoPath("tracked.txt")],
        untracked: [],
      }),
    ),
    null,
  );
  assert.deepEqual(await readdir(previewScratch), []);
});

test("typed pins including annotated tag, stash and reflog candidate survive a no-prerequisite bundle proof", async (t) => {
  const legacy = await dirtyLegacy(t, "bundle");
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  const stage: StageHandle = await request({
    source: legacy.source,
    head: legacy.head,
    scratchRoot: scratch,
  });
  assert.ok(stage.snapshot);

  const pin = (base: {
    sourceKind: PinIntent["sourceKind"];
    sourceName: string;
    sourceOid: string;
    objectType: PinIntent["objectType"];
  }): PinIntent => {
    const sourceOid = base.sourceOid as Oid;
    return {
      sourceKind: base.sourceKind,
      sourceName: base.sourceName,
      sourceOid,
      objectType: base.objectType,
      destinationOid: sourceOid,
      destinationRef: pinRef(
        { ...base, sourceOid, destinationOid: sourceOid },
        "legacy",
        "g0",
        base.sourceKind === "working-copy" && stage.snapshot !== null
          ? { parentOid: stage.snapshot.parentOid, treeOid: stage.snapshot.treeOid }
          : null,
      ),
    };
  };
  const snapshotCommit = stage.snapshot.commitOid;
  const pins: readonly PinIntent[] = [
    pin({ sourceKind: "head", sourceName: "HEAD", sourceOid: legacy.head, objectType: "commit" }),
    pin({
      sourceKind: "branch",
      sourceName: legacy.branchRef,
      sourceOid: legacy.head,
      objectType: "commit",
    }),
    pin({
      sourceKind: "tag",
      sourceName: "refs/tags/v1",
      sourceOid: legacy.annotatedTagOid,
      objectType: "tag",
    }),
    pin({
      sourceKind: "tag",
      sourceName: "refs/tags/lw",
      sourceOid: legacy.head,
      objectType: "commit",
    }),
    pin({
      sourceKind: "stash",
      sourceName: "refs/stash",
      sourceOid: legacy.stashTipOid,
      objectType: "commit",
    }),
    pin({
      sourceKind: "reflog",
      sourceName: candidateIdentity("stash-older", legacy.olderStashOid as Oid),
      sourceOid: legacy.olderStashOid,
      objectType: "commit",
    }),
    pin({
      sourceKind: "working-copy",
      sourceName: "working-copy",
      sourceOid: snapshotCommit,
      objectType: "commit",
    }),
  ];

  const before = await fingerprintsOf(legacy.source);
  const proven = await proveBundle(stage, pins);
  assert.equal(proven.freshRestoreVerified, true);
  assert.equal(proven.snapshotManifestVerified, true);
  assert.deepEqual(
    new Map(proven.verifiedHeads.map(({ ref, oid }) => [ref as string, oid as string])),
    new Map(
      pins.map(({ destinationRef, destinationOid }) => [
        destinationRef as string,
        destinationOid as string,
      ]),
    ),
  );
  assert.match(proven.bundleSha256, /^[0-9a-f]{64}$/);
  // The annotated tag object round-trips as a tag, peeling to a commit.
  assert.equal(await run(proven.restoreRepoPath, "cat-file", "-t", legacy.annotatedTagOid), "tag");
  await run(proven.restoreRepoPath, "rev-parse", `${legacy.annotatedTagOid}^{commit}`);
  // Every snapshot blob is present; binary and symlink content survive.
  const weird = stage.snapshot.paths.find(({ path }) => path === "we*ird [na]mé.txt");
  assert.ok(weird);
  const weirdBytes = (
    await Effect.runPromise(
      git(["cat-file", "blob", weird.blobOid], { cwd: proven.restoreRepoPath }),
    )
  ).stdout;
  assert.equal(utf8Fatal(weirdBytes), "weird name");
  const link = stage.snapshot.paths.find(({ path }) => path === "abs-link");
  assert.equal(
    utf8Fatal(
      (
        await Effect.runPromise(
          git(["cat-file", "blob", link?.blobOid ?? ""], { cwd: proven.restoreRepoPath }),
        )
      ).stdout,
    ),
    "/etc/hostname",
  );
  // Stage is detached from the source once the proof is done.
  await assert.rejects(() => readFile(join(stage.gitDir, "objects", "info", "alternates")));
  assert.deepEqual(await fingerprintsOf(legacy.source), before);

  // The bundle alone restores after the source directory is renamed away.
  const gone = join(legacy.root, "source-gone");
  await rename(legacy.source, gone);
  const fresh = join(legacy.root, "fresh.git");
  await run(legacy.root, "init", "--quiet", "--bare", fresh);
  await run(fresh, "bundle", "verify", proven.bundlePath);
  await run(fresh, "fetch", "--quiet", proven.bundlePath, "+refs/*:refs/*");
  const restored = await run(fresh, "for-each-ref", "--format=%(refname)%00%(objectname)");
  const restoredMap = new Map(
    restored
      .split("\n")
      .filter((line) => line !== "")
      .map((line) => {
        const [ref, oidValue] = line.split("\0");
        return [ref, oidValue];
      }),
  );
  assert.deepEqual(
    restoredMap,
    new Map(
      pins.map(({ destinationRef, destinationOid }) => [
        destinationRef as string,
        destinationOid as string,
      ]),
    ),
  );
  const manifest = await run(fresh, "ls-tree", "-r", "-z", stage.snapshot?.commitOid ?? "HEAD");
  const manifestPaths = manifest
    .split("\0")
    .filter((record) => record !== "")
    .map((record) => record.slice(record.indexOf("\t") + 1));
  assert.deepEqual(
    manifestPaths,
    stage.snapshot.paths.map(({ path }) => path as string),
  );
});

test("tree- and blob-tipped pins are refused even though installed git can mechanically bundle them", async (t) => {
  const legacy = await dirtyLegacy(t, "tree-blob-block");
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  const stage = await request({ source: legacy.source, head: legacy.head, scratchRoot: scratch });

  // Positive control on a throwaway repo: git 2.55 itself round-trips a
  // tree-tip ref through `bundle create`. Custody still does not promise it.
  const control = join(legacy.root, "control");
  await mkdir(control);
  await run(control, "init", "--quiet");
  await writeFile(join(control, "a.txt"), "a\n");
  await run(control, ...identity, "add", "-A", ".");
  await run(control, ...identity, "commit", "--quiet", "-m", "one");
  const controlTree = await run(control, "rev-parse", "HEAD^{tree}");
  await run(control, "update-ref", "refs/adopt/tree-tip", controlTree);
  const controlBundle = join(control, "tree.bundle");
  const created = await Effect.runPromise(
    git(["bundle", "create", controlBundle, "--all"], { cwd: control }),
  );
  assert.equal(created.exitCode, 0, "documented: installed git accepts tree-tip bundle refs");

  const treePin: PinIntent = {
    sourceKind: "reflog",
    sourceName: candidateIdentity("dangling", stage.headTreeOid),
    sourceOid: stage.headTreeOid,
    objectType: "tree",
    destinationOid: stage.headTreeOid,
    destinationRef: pinRef(
      {
        sourceKind: "reflog",
        sourceName: candidateIdentity("dangling", stage.headTreeOid),
        sourceOid: stage.headTreeOid,
        destinationOid: stage.headTreeOid,
      },
      "legacy",
      "g0",
    ),
  };
  const treeError = await custodyError(proveBundle(stage, [treePin]));
  assert.equal(treeError.code, "unsupported-repository");
  assert.match(treeError.message, /tree tips/);
  const blob = stage.snapshot?.paths[0]?.blobOid;
  assert.ok(blob);
  const blobPin: PinIntent = {
    ...treePin,
    objectType: "blob",
    sourceOid: blob,
    destinationOid: blob,
    destinationRef: pinRef(
      {
        sourceKind: "reflog",
        sourceName: candidateIdentity("dangling", blob),
        sourceOid: blob,
        destinationOid: blob,
      },
      "legacy",
      "g0",
    ),
  };
  const blobError = await custodyError(proveBundle(stage, [blobPin]));
  assert.equal(blobError.code, "unsupported-repository");
  assert.match(blobError.message, /blob tips/);
});

test("expected-manifest mismatch, filters, missing review and nested scratch are refused without touching the source", async (t) => {
  const legacy = await dirtyLegacy(t, "refusals");
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  const baseline = await request({
    source: legacy.source,
    head: legacy.head,
    scratchRoot: scratch,
  });
  assert.ok(baseline.snapshot);

  // Create a real staged/unstaged split: stage staged-only.txt in the source
  // index. The synthetic tree is unchanged, but "reported-not-preserved" now
  // needs an explicit single-tree approval in the path review.
  await run(legacy.source, "add", "staged-only.txt");
  const before = await fingerprintsOf(legacy.source);

  const wrong = baseline.snapshot.paths.map((entry, index) =>
    index === 0
      ? {
          ...entry,
          blobOid:
            `${entry.blobOid.slice(0, 39)}${entry.blobOid.slice(39) === "0" ? "1" : "0"}` as Oid,
        }
      : entry,
  );
  const drift = await custodyError(
    request({ source: legacy.source, head: legacy.head, scratchRoot: scratch, expected: wrong }),
  );
  assert.equal(drift.code, "source-drift");
  assert.match(drift.message, /differs from the reviewed manifest/);

  await writeFile(join(legacy.source, ".gitattributes"), "untracked.txt filter=broken\n");
  const filtered = await custodyError(
    request({
      source: legacy.source,
      head: legacy.head,
      scratchRoot: scratch,
      untracked: [repoPath("untracked.txt")],
      stagedVsUnstaged: "reported-not-preserved",
    }),
  );
  assert.equal(filtered.code, "unsupported-repository");
  assert.match(filtered.message, /filter/);
  await rm(join(legacy.source, ".gitattributes"));

  const secret = baseline.snapshot.paths.find(({ path }) => path === legacy.secretKey);
  assert.ok(secret);
  const reviewInput = {
    schema: "compfuzor.archive-path-review/v1",
    manifestSha256: sha256(Buffer.from(`${canonicalJson(baseline.snapshot.paths)}\n`)),
    included: [
      {
        path: secret.path,
        mode: secret.mode,
        blobOid: secret.blobOid,
        classification: "credential",
        decision: "local-custody-approved",
        reason: "local custody only",
      },
    ],
    stagedVsUnstaged: null,
  };
  const review = parsePathReview(Buffer.from(JSON.stringify(reviewInput)), "sha1");
  const noApproval = await custodyError(
    request({
      source: legacy.source,
      head: legacy.head,
      scratchRoot: scratch,
      sensitive: [legacy.secretKey],
      review,
      stagedVsUnstaged: "reported-not-preserved",
    }),
  );
  assert.equal(noApproval.code, "invalid-input");
  assert.match(noApproval.message, /single-tree approval/);

  const approved = parsePathReview(
    Buffer.from(
      JSON.stringify({
        ...reviewInput,
        stagedVsUnstaged: { decision: "single-tree-approved", reason: "one tree is enough" },
      }),
    ),
    "sha1",
  );
  const reviewed = await request({
    source: legacy.source,
    head: legacy.head,
    scratchRoot: scratch,
    sensitive: [legacy.secretKey],
    review: approved,
    stagedVsUnstaged: "reported-not-preserved",
    expected: baseline.snapshot.paths,
  });
  assert.ok(reviewed.snapshot);
  assert.deepEqual(reviewed.snapshot.paths, baseline.snapshot.paths);
  assert.deepEqual(reviewed.snapshotCommitOid, baseline.snapshotCommitOid);
  assert.equal(reviewed.snapshot.stagedVsUnstaged, "reported-not-preserved");

  const inside = join(legacy.source, ".scratch-inside");
  await mkdir(inside);
  const nested = await custodyError(
    request({ source: legacy.source, head: legacy.head, scratchRoot: inside }),
  );
  assert.equal(nested.code, "invalid-input");
  assert.match(nested.message, /outside the source/);
  await rm(inside, { recursive: true });

  assert.deepEqual(await fingerprintsOf(legacy.source), before, "refusals never mutate the source");
});

test("previewSnapshot breaks the review chicken-and-egg without weakening the apply door", async (t) => {
  const legacy = await dirtyLegacy(t, "preview");
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  // A real staged split plus a sensitive tracked path: the exact state whose
  // approval `prepareSnapshot` requires before it will stage anything.
  await run(legacy.source, "add", "staged-only.txt");
  const before = await fingerprintsOf(legacy.source);
  const ask = {
    source: legacy.source,
    head: legacy.head,
    scratchRoot: scratch,
    sensitive: [legacy.secretKey],
    stagedVsUnstaged: "reported-not-preserved" as const,
  };

  const preview = await previewSnapshot(snapshotInput(ask));
  assert.ok(preview, "a dirty preview carries the shared SnapshotProposal");
  assert.equal(preview.format, "worktree-v1");
  assert.equal(preview.parentOid, legacy.head);
  assert.ok(preview.commitOid, "a dirty preview carries the deterministic commit identity");
  assert.equal(preview.paths.length > 0, true);
  assert.equal(preview.manifestSha256, sha256(Buffer.from(`${canonicalJson(preview.paths)}\n`)));
  assert.deepEqual(preview.reviewRequirements.sensitivePaths, [legacy.secretKey]);
  assert.equal(preview.reviewRequirements.stagedVsUnstagedApprovalRequired, true);
  // Plain data only: no stage location leaks out of the preview door.
  assert.equal("gitDir" in preview, false);
  assert.equal("stageRoot" in preview, false);
  // The throwaway scratch is disposed, and the source is untouched.
  assert.deepEqual(await readdir(scratch), []);
  assert.deepEqual(await fingerprintsOf(legacy.source), before);

  // Apply refuses the same inputs without a manifest-bound review…
  const refused = await custodyError(request(ask));
  assert.equal(refused.code, "invalid-input");
  assert.match(refused.message, /path review/);

  // …including a review bound to some other manifest.
  const reviewInput = {
    schema: "compfuzor.archive-path-review/v1",
    manifestSha256: "0".repeat(64),
    included: [],
    stagedVsUnstaged: { decision: "single-tree-approved", reason: "bound to nothing" },
  };
  const unbound = await custodyError(
    request({ ...ask, review: parsePathReview(Buffer.from(JSON.stringify(reviewInput)), "sha1") }),
  );
  assert.equal(unbound.code, "invalid-input");
  assert.match(unbound.message, /digest does not match/);

  // A review authored against the preview's exact digest and manifest opens
  // the apply door, and the applied snapshot is exactly what was previewed.
  const secret = preview.paths.find(({ path }) => path === legacy.secretKey);
  assert.ok(secret);
  const review = parsePathReview(
    Buffer.from(
      JSON.stringify({
        ...reviewInput,
        manifestSha256: preview.manifestSha256,
        included: [
          {
            path: secret.path,
            mode: secret.mode,
            blobOid: secret.blobOid,
            classification: "credential",
            decision: "local-custody-approved",
            reason: "approved from preview digest",
          },
        ],
      }),
    ),
    "sha1",
  );
  const stage = await request({ ...ask, review, expected: preview.paths });
  assert.ok(stage.snapshot);
  assert.deepEqual(stage.snapshot.paths, preview.paths);
  assert.equal(stage.snapshot.commitOid, preview.commitOid);
  assert.deepEqual(
    await fingerprintsOf(legacy.source),
    before,
    "neither door ever mutates the source",
  );
});

test("tracked .jj internals block staging and .git/.jj input paths are refused outright", async (t) => {
  const home = await area(t, "internals");
  await run(home.source, "init", "--quiet");
  await writeFile(join(home.source, "plain.txt"), "data\n");
  await mkdir(join(home.source, ".jj"));
  await writeFile(join(home.source, ".jj", "inert"), "placeholder\n");
  await run(home.source, ...identity, "add", "-A", ".");
  await run(home.source, ...identity, "commit", "--quiet", "-m", "with-jj-internals");
  const head = await run(home.source, "rev-parse", "HEAD");
  const scratch = join(home.root, "scratch");
  await mkdir(scratch);
  const blocked = await custodyError(
    prepareSnapshot({
      sourceRoot: home.source,
      scratchRoot: scratch,
      objectFormat: "sha1",
      headOid: head as Oid,
      restageTracked: [],
      addUntracked: [],
      stagedVsUnstaged: "none",
      excludeFileSha256: null,
      excludedUntracked: [],
      ignoredPaths: [],
      trackedSensitivePaths: [],
      pathReview: null,
      expected: null,
    }),
  );
  assert.equal(blocked.code, "unsupported-repository");
  assert.match(blocked.message, /\.jj/);

  const refused = await custodyError(
    request({
      source: home.source,
      head,
      scratchRoot: scratch,
      restage: [],
      untracked: [repoPath("sub/.git/config")],
    }),
  );
  assert.equal(refused.code, "invalid-input");
  assert.match(refused.message, /\.git\/\.jj/);
});

test("sha256 sources stage and prove with 64-hex custody identities", async (t) => {
  const legacy = await dirtyLegacy(t, "sha256", "sha256");
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  const stage = await prepareSnapshot({
    sourceRoot: legacy.source,
    scratchRoot: scratch,
    objectFormat: "sha256",
    headOid: legacy.head as Oid,
    restageTracked: restageDefaults(),
    addUntracked: untrackedDefaults(),
    stagedVsUnstaged: "none",
    excludeFileSha256: null,
    excludedUntracked: [],
    ignoredPaths: [repoPath("runtime.ignored")],
    trackedSensitivePaths: [],
    pathReview: null,
    expected: null,
  });
  assert.ok(stage.snapshot);
  assert.match(stage.snapshot.commitOid, /^[0-9a-f]{64}$/);
  const snapshotCommit = stage.snapshot.commitOid;
  const headOid = legacy.head as Oid;
  const headPin: PinIntent = {
    sourceKind: "head",
    sourceName: "HEAD",
    sourceOid: headOid,
    objectType: "commit",
    destinationOid: headOid,
    destinationRef: pinRef(
      { sourceKind: "head", sourceName: "HEAD", sourceOid: headOid, destinationOid: headOid },
      "legacy",
      "g0",
    ),
  };
  const workPin: PinIntent = {
    sourceKind: "working-copy",
    sourceName: "working-copy",
    sourceOid: snapshotCommit,
    objectType: "commit",
    destinationOid: snapshotCommit,
    destinationRef: pinRef(
      {
        sourceKind: "working-copy",
        sourceName: "working-copy",
        sourceOid: snapshotCommit,
        destinationOid: snapshotCommit,
      },
      "legacy",
      "g0",
      { parentOid: stage.snapshot.parentOid, treeOid: stage.snapshot.treeOid },
    ),
  };
  const proven = await proveBundle(stage, [headPin, workPin]);
  assert.equal(proven.verifiedHeads.length, 2);
  assert.equal(proven.snapshotManifestVerified, true);
});

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));
const pathExists = async (file: string): Promise<boolean> => {
  try {
    await readFile(file);
    return true;
  } catch {
    return false;
  }
};
const waitFor = async (file: string, ms = 4000): Promise<boolean> => {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (await pathExists(file)) return true;
    await sleep(20);
  }
  return false;
};

/**
 * Controllable-process fixture: a `git` shim on PATH blocks the named
 * subcommand until released (touching `killed` on TERM), everything else
 * passes through to the real git. Proves aborting the execution signal kills
 * the in-flight stage child and that no ref/bundle/restore work continues.
 */
test("aborting an execution kills the in-flight Git child and stops all further stage work", async (t) => {
  const legacy = await dirtyLegacy(t, "abort");
  const scratch = join(legacy.root, "scratch");
  await mkdir(scratch);
  const stage = await request({ source: legacy.source, head: legacy.head, scratchRoot: scratch });
  assert.ok(stage.snapshot);
  const headPin: PinIntent = {
    sourceKind: "head",
    sourceName: "HEAD",
    sourceOid: legacy.head as Oid,
    objectType: "commit",
    destinationOid: legacy.head as Oid,
    destinationRef: pinRef(
      {
        sourceKind: "head",
        sourceName: "HEAD",
        sourceOid: legacy.head as Oid,
        destinationOid: legacy.head as Oid,
      },
      "legacy",
      "g0",
    ),
  };
  const snapshotCommit = stage.snapshot.commitOid;
  const workPin: PinIntent = {
    sourceKind: "working-copy",
    sourceName: "working-copy",
    sourceOid: snapshotCommit,
    objectType: "commit",
    destinationOid: snapshotCommit,
    destinationRef: pinRef(
      {
        sourceKind: "working-copy",
        sourceName: "working-copy",
        sourceOid: snapshotCommit,
        destinationOid: snapshotCommit,
      },
      "legacy",
      "g0",
      { parentOid: stage.snapshot.parentOid, treeOid: stage.snapshot.treeOid },
    ),
  };

  const bin = join(legacy.root, "bin");
  const mark = join(legacy.root, "mark");
  await mkdir(bin);
  await mkdir(mark);
  const realPath = process.env.PATH ?? "";
  await writeFile(join(bin, "realpath"), `${realPath}\n`);
  await writeFile(join(bin, "control"), "none\n");
  await writeFile(join(bin, "mark"), `${mark}\n`);
  const shim = join(bin, "git");
  await writeFile(
    shim,
    [
      "#!/bin/sh",
      'BIN=$(dirname "$0")',
      'BLOCKED=$(cat "$BIN/control" 2>/dev/null || printf none)',
      'MARK=$(cat "$BIN/mark" 2>/dev/null || printf "$BIN")',
      'for a in "$@"; do',
      '  if [ "$a" = "$BLOCKED" ]; then',
      "    trap 'touch \"$MARK/killed\"; exit 9' TERM INT",
      '    touch "$MARK/started"',
      '    while [ ! -e "$MARK/release" ]; do sleep 0.02; done',
      '    touch "$MARK/completed"',
      "    exit 42",
      "  fi",
      "done",
      'PATH="$(cat "$BIN/realpath")" exec git "$@"',
      "",
    ].join("\n"),
  );
  await chmod(shim, 0o755);
  process.env.PATH = `${bin}:${realPath}`;
  t.after(() => {
    process.env.PATH = realPath;
  });

  try {
    // Block the very first pin update-ref; abort mid-flight.
    await writeFile(join(bin, "control"), "update-ref\n");
    const controller = new AbortController();
    const pending = proveBundle(stage, [headPin, workPin], { signal: controller.signal });
    assert.equal(await waitFor(join(mark, "started")), true, "blocked git invocation reached");
    controller.abort();
    const failure = await pending.then(
      () => null,
      (error: unknown) => error,
    );
    assert.ok(failure instanceof Error, `expected the abort to reject, got ${String(failure)}`);
    assert.equal((failure as Error & { name?: string }).name, "AbortError");
    assert.equal(
      await waitFor(join(mark, "killed")),
      true,
      "the in-flight stage child was terminated (not orphaned)",
    );
    // Nothing after the abort point ran: no pin refs, no repack/bundle, no
    // restore; the alternates pointer survives for diagnosis.
    assert.equal(await run(stage.gitDir, "for-each-ref"), "");
    assert.equal(await pathExists(join(stage.gitDir, "objects", "info", "alternates")), true);
    assert.equal(await pathExists(join(stage.stageRoot, "source.bundle")), false);
    assert.deepEqual((await readdir(stage.stageRoot)).sort(), ["pathspec.nul", "stage.git"]);
    // The blocked loop is dead, not paused: releasing it cannot complete.
    await writeFile(join(mark, "release"), "now\n");
    await sleep(250);
    assert.equal(await pathExists(join(mark, "completed")), false);

    // Preview abort: the throwaway scratch is cleaned only after the
    // interrupted child finalized, and abort is not masked as a Git failure.
    const mark2 = join(legacy.root, "mark2");
    await mkdir(mark2);
    await writeFile(join(bin, "mark"), `${mark2}\n`);
    await writeFile(join(bin, "control"), "commit-tree\n");
    const previewScratch = join(legacy.root, "preview-scratch");
    await mkdir(previewScratch);
    const previewController = new AbortController();
    const previewPending = previewSnapshot(
      snapshotInput({ source: legacy.source, head: legacy.head, scratchRoot: previewScratch }),
      { signal: previewController.signal },
    );
    assert.equal(await waitFor(join(mark2, "started")), true);
    previewController.abort();
    const previewFailure = await previewPending.then(
      () => null,
      (error: unknown) => error,
    );
    assert.ok(previewFailure instanceof Error);
    assert.equal((previewFailure as Error & { name?: string }).name, "AbortError");
    assert.equal(await waitFor(join(mark2, "killed")), true);
    assert.deepEqual(await readdir(previewScratch), [], "preview scratch disposed after abort");
  } finally {
    // Release any hypothetical straggler and restore the real PATH.
    await writeFile(join(mark, "release"), "now\n");
    await writeFile(join(bin, "control"), "none\n");
    process.env.PATH = realPath;
  }
});
