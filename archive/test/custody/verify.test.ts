import assert from "node:assert/strict";
import {
  mkdir,
  mkdtemp,
  chmod,
  chown,
  readFile,
  readdir,
  readlink,
  realpath,
  rename,
  rm,
  stat,
  symlink,
  writeFile,
} from "node:fs/promises";
import { dirname, join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { test } from "node:test";
import { Effect } from "effect";
import { gitChecked, gitRead, utf8Fatal } from "../../src/repository/git.ts";
import { jj } from "../../src/repository/jj.ts";
import {
  candidateIdentity,
  canonicalJson,
  destinationRefsSha256,
  encodeReceipt,
  oid,
  pinRef,
  receiptRef,
  refName,
  repoPath,
  sha256,
} from "../../src/custody/codec.ts";
import { CustodyError } from "../../src/custody/errors.ts";
import { applyAdoption } from "../../src/custody/apply.ts";
import type {
  GitObjectType,
  GitTip,
  IndexEntry,
  Oid,
  PathEntry,
  PinIntent,
  ReceiptV1,
  RefName,
  Verification,
} from "../../src/custody/model.ts";
import { prepareSnapshot, proveBundle } from "../../src/custody/stage.ts";
import { readReceipt, verifyAdoption } from "../../src/custody/verify.ts";
import {
  createVaultRun,
  readVaultBundle,
  resolveVaultBundle,
  sealBundle,
  sealVaultFile,
  VAULT_DIRNAME,
  vaultArchiveId,
  vaultRunId,
  VaultPathComponentError,
} from "../../src/custody/vault.ts";

// Every fixture is disposable scratch under .test-agent; production archives
// are never touched. Adoptions here are manually assembled from REAL Git
// objects: a dirty legacy checkout staged through custody/stage.ts, a real
// proven bundle, a real destination Git repository, a real metadata commit,
// and a real sibling vault — so the verifier exercises actual Git state.
const scratchRoot = join(import.meta.dirname, "..", "..", "..", ".test-agent", "custody-verify");
const encoder = new TextEncoder();
const identity = [
  "-c",
  "user.name=custody",
  "-c",
  "user.email=custody@example.invalid",
  "-c",
  "commit.gpgsign=false",
] as const;
const REF_FORMAT = "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(*objectname)%00";
const RECEIPT_REF = receiptRef("legacy", "g0");

const run = async (cwd: string, ...args: string[]): Promise<string> =>
  utf8Fatal(await Effect.runPromise(gitChecked(args, { cwd }))).trim();

const runInput = async (
  cwd: string,
  args: readonly string[],
  input: Uint8Array,
  env?: Record<string, string>,
): Promise<string> =>
  utf8Fatal(await Effect.runPromise(gitChecked(args, { cwd, input, env }))).trim();

/** The exact status fingerprint inventory records (same argv and env). */
const statusBytes = async (repo: string): Promise<Uint8Array> =>
  (
    await Effect.runPromise(
      gitRead(["status", "--porcelain=v2", "-z", "--untracked-files=all"], { cwd: repo }),
    )
  ).stdout;

export async function area(
  t: { after: (hook: () => Promise<unknown>) => void },
  name: string,
): Promise<string> {
  await mkdir(scratchRoot, { recursive: true });
  const root = await mkdtemp(join(scratchRoot, `${name}-`));
  t.after(async () => {
    await rm(root, { recursive: true, force: true });
  });
  return root;
}

/** `ls-tree -r -z` → sorted canonical path/mode/blob manifest. */
function parseManifest(bytes: Uint8Array): PathEntry[] {
  const entries: PathEntry[] = [];
  for (const record of utf8Fatal(bytes).split("\0")) {
    if (record === "") continue;
    const tab = record.indexOf("\t");
    const [mode, type, blobOid] = record.slice(0, tab).split(" ");
    assert.equal(type, "blob");
    entries.push({
      path: repoPath(record.slice(tab + 1)),
      mode: mode as PathEntry["mode"],
      blobOid: oid(blobOid, "sha1"),
    });
  }
  entries.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return entries;
}

function parseTips(bytes: Uint8Array): GitTip[] {
  const tips: GitTip[] = [];
  // runInput trims the trailing newline; filter instead of slicing it off.
  for (const line of utf8Fatal(bytes)
    .split("\n")
    .filter((entry) => entry !== "")) {
    const [name, target, type, peeled] = line.split("\0");
    tips.push({
      name: refName(name),
      oid: oid(target, "sha1"),
      objectType: type as GitObjectType,
      peeledOid: peeled === "" ? null : oid(peeled, "sha1"),
    });
  }
  return tips;
}

function parseIndex(bytes: Uint8Array): IndexEntry[] {
  const entries: IndexEntry[] = [];
  for (const record of utf8Fatal(bytes).split("\0")) {
    if (record === "") continue;
    const tab = record.indexOf("\t");
    const [mode, blobOid, stage] = record.slice(0, tab).split(" ");
    entries.push({
      path: repoPath(record.slice(tab + 1)),
      mode: mode as PathEntry["mode"],
      blobOid: oid(blobOid, "sha1"),
      stage: Number(stage) as IndexEntry["stage"],
    });
  }
  entries.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return entries;
}

/** Fingerprint lines for mutation detection: `path sha256` / `path -> target`. */
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

export interface Adoption {
  readonly root: string;
  readonly source: string;
  readonly dest: string;
  readonly destReal: string;
  readonly scratch: string;
  readonly receipt: ReceiptV1;
  readonly receiptCommitOid: Oid;
  readonly receiptRef: RefName;
  readonly pins: readonly PinIntent[];
  readonly bundlePath: string;
  readonly vaultRunDir: string;
}
const commitEnv = {
  GIT_AUTHOR_NAME: "compfuzor archive",
  GIT_AUTHOR_EMAIL: "archive@compfuzor.invalid",
  GIT_COMMITTER_NAME: "compfuzor archive",
  GIT_COMMITTER_EMAIL: "archive@compfuzor.invalid",
  GIT_AUTHOR_DATE: "@0 +0000",
  GIT_COMMITTER_DATE: "@0 +0000",
};

/** Install `adoption.json` as a new metadata commit and repoint the receipt ref. */
async function installReceiptBlob(
  dest: string,
  receiptRefName: string,
  bytes: Uint8Array,
): Promise<string> {
  const blob = await runInput(dest, ["hash-object", "-w", "--stdin"], bytes);
  const tree = await runInput(
    dest,
    ["mktree"],
    encoder.encode(`100644 blob ${blob}\tadoption.json\n`),
  );
  const commit = await runInput(
    dest,
    ["commit-tree", tree, "-m", "compfuzor adoption receipt"],
    new Uint8Array(),
    commitEnv,
  );
  await run(dest, "update-ref", receiptRefName, commit);
  return commit;
}

/**
 * A complete, real adoption fixture: dirty legacy source (branch, annotated +
 * lightweight tags, two-entry stash), private stage snapshot, proven bundle,
 * destination repository with all custody refs imported, metadata receipt
 * commit, and a sibling vault holding the bundle. `jjColocate` builds the
 * destination with jj instead of plain Git.
 */
export async function adoption(
  t: { after: (hook: () => Promise<unknown>) => void },
  name: string,
  options: {
    readonly jjColocate?: boolean;
    readonly specialPaths?: boolean;
    readonly attributedDest?: boolean;
  } = {},
): Promise<Adoption> {
  const root = await area(t, name);
  const source = join(root, "legacy");
  const scratch = join(root, "scratch");
  const dest = join(root, "archive");

  // --- legacy source ---
  await run(root, "init", "--quiet", "--initial-branch=main", source);
  await writeFile(join(source, "README.md"), "readme\n");
  await writeFile(join(source, "tracked.txt"), "hello\n");
  await writeFile(join(source, ".gitignore"), "*.ignored\n");
  if (options.specialPaths) {
    await writeFile(join(source, "line\nbreak"), "newline filename\n");
    await mkdir(join(source, "nested"));
    await writeFile(join(source, "nested", "inside"), "inside bytes\n");
    const outside = join(root, "outside-target");
    await writeFile(outside, "outside contents\n");
    await symlink(outside, join(source, "link"));
  }
  await run(source, ...identity, "add", "-A", ".");
  await run(source, ...identity, "commit", "--quiet", "-m", "base");
  const head = oid(await run(source, "rev-parse", "HEAD"), "sha1");
  const headTree = oid(await run(source, "rev-parse", `${head}^{tree}`), "sha1");
  await run(source, "branch", "topic");
  await run(source, ...identity, "tag", "-a", "v1", "-m", "annotated");
  await run(source, "tag", "lw");
  // Two stash entries: the tip is pinned through refs/stash, the older one
  // through the reflog candidate lane — exactly the split custody promises.
  await writeFile(join(source, "tracked.txt"), "changed\n");
  const olderStash = oid(await run(source, ...identity, "stash", "create"), "sha1");
  await run(source, "stash", "store", "-m", "older", olderStash);
  await writeFile(join(source, "tracked.txt"), "changed-again\n");
  const stashTip = oid(await run(source, ...identity, "stash", "create"), "sha1");
  await run(source, "stash", "store", "-m", "current", stashTip);
  await writeFile(join(source, "untracked.txt"), "untracked\n");

  const sourceGitDir = await run(source, "rev-parse", "--absolute-git-dir");
  const symbolic = await run(source, "symbolic-ref", "--quiet", "HEAD");
  const refsRaw = await runInput(source, ["for-each-ref", REF_FORMAT], new Uint8Array());
  const gitTips = parseTips(encoder.encode(refsRaw));
  const treePaths = parseManifest(
    await Effect.runPromise(gitChecked(["ls-tree", "-r", "-z", headTree], { cwd: source })),
  );
  const indexEntries = parseIndex(
    await Effect.runPromise(gitChecked(["ls-files", "--stage", "-z"], { cwd: source })),
  );
  const indexBytes = await readFile(join(sourceGitDir, "index"));
  const configBytes = await readFile(join(sourceGitDir, "config"));
  const reflogBytes = await Effect.runPromise(
    gitChecked(["reflog", "show", "--all"], { cwd: source }),
  );

  // --- private stage + complete bundle proof ---
  await mkdir(scratch);
  const stage = await prepareSnapshot({
    sourceRoot: source,
    scratchRoot: scratch,
    objectFormat: "sha1",
    headOid: head,
    restageTracked: [repoPath("tracked.txt")],
    addUntracked: [repoPath("untracked.txt")],
    stagedVsUnstaged: "none",
    excludeFileSha256: null,
    excludedUntracked: [],
    ignoredPaths: [],
    trackedSensitivePaths: [],
    pathReview: null,
    expected: null,
  });
  assert.notEqual(stage.snapshot, null);
  const snapshot = stage.snapshot as NonNullable<typeof stage.snapshot>;

  const candidate = {
    kind: "stash-older" as const,
    oid: olderStash,
    objectType: "commit" as const,
    provenance: ["refs/stash@{1}"],
    disposition: "pin" as const,
    reason: null,
  };
  const pins: PinIntent[] = [
    {
      sourceKind: "head",
      sourceName: "HEAD",
      sourceOid: head,
      objectType: "commit",
      destinationOid: head,
      destinationRef: pinRef(
        { sourceKind: "head", sourceName: "HEAD", sourceOid: head, destinationOid: head },
        "legacy",
        "g0",
      ),
    },
    ...gitTips.map((tip): PinIntent => {
      const sourceKind: PinIntent["sourceKind"] = tip.name.startsWith("refs/heads/")
        ? "branch"
        : tip.name.startsWith("refs/tags/")
          ? "tag"
          : tip.name === "refs/stash"
            ? "stash"
            : "other";
      return {
        sourceKind,
        sourceName: tip.name,
        sourceOid: tip.oid,
        objectType: tip.objectType,
        destinationOid: tip.oid,
        destinationRef: pinRef(
          {
            sourceKind,
            sourceName: tip.name,
            sourceOid: tip.oid,
            destinationOid: tip.oid,
          },
          "legacy",
          "g0",
        ),
      };
    }),
    {
      sourceKind: "reflog",
      sourceName: candidateIdentity(candidate.kind, candidate.oid),
      sourceOid: candidate.oid,
      objectType: candidate.objectType,
      destinationOid: candidate.oid,
      destinationRef: pinRef(
        {
          sourceKind: "reflog",
          sourceName: candidateIdentity(candidate.kind, candidate.oid),
          sourceOid: candidate.oid,
          destinationOid: candidate.oid,
        },
        "legacy",
        "g0",
      ),
    },
    {
      sourceKind: "working-copy",
      sourceName: "working-copy",
      sourceOid: snapshot.commitOid,
      objectType: "commit",
      destinationOid: snapshot.commitOid,
      destinationRef: pinRef(
        {
          sourceKind: "working-copy",
          sourceName: "working-copy",
          sourceOid: snapshot.commitOid,
          destinationOid: snapshot.commitOid,
        },
        "legacy",
        "g0",
        snapshot,
      ),
    },
  ];
  const proven = await proveBundle(stage, pins);

  // --- destination archive ---
  if (options.jjColocate === true) {
    await jj(["git", "init", "--colocate", dest], root);
  } else {
    await run(root, "init", "--quiet", "--initial-branch=main", dest);
  }
  await writeFile(join(dest, "archive-readme.md"), "archive\n");
  if (options.attributedDest)
    await writeFile(join(dest, ".gitattributes"), "archive-readme.md filter=unsafe\n");
  await run(dest, ...identity, "add", "-A", ".");
  await run(dest, ...identity, "commit", "--quiet", "-m", "archive base");
  const destReal = await realpath(dest);
  const destRefBytes = await runInput(dest, ["for-each-ref", REF_FORMAT], new Uint8Array());
  const destTips = parseTips(encoder.encode(destRefBytes));
  const destStatus = await statusBytes(dest);
  const destIndexBytes = await readFile(join(dest, ".git", "index"));

  // --- import custody objects and refs, install the receipt ---
  await run(dest, "-c", "gc.auto=0", "fetch", "--quiet", proven.bundlePath, "+refs/*:refs/*");

  // Seal the proven bundle + signed-off intent through the durable writer.
  const sealed = await sealBundle({
    destRealpath: destReal,
    legacyRealpath: await realpath(source),
    proven: {
      bundlePath: proven.bundlePath,
      bundleSha256: proven.bundleSha256,
      verifiedHeads: proven.verifiedHeads,
      freshRestoreVerified: proven.freshRestoreVerified,
    },
    intent: encoder.encode(
      `${canonicalJson({ schema: "compfuzor.archive-adoption-intent/v1", label: "legacy", generation: "g0" })}\n`,
    ),
  });
  const vaultRunDir = sealed.run.runDir;

  const receipt: ReceiptV1 = {
    schema: "compfuzor.archive-adoption/v1",
    receiptRef: RECEIPT_REF,
    identity: {
      label: "legacy",
      generation: "g0",
      legacyRealpathAtCapture: await realpath(source),
      sourceGitCommonDir: sourceGitDir,
      destinationRealpath: destReal,
      createdAt: "2026-09-28T00:00:00.000Z",
    },
    source: {
      objectFormat: "sha1",
      sourceGitCommonDir: sourceGitDir,
      head: {
        symbolicRef: refName(symbolic),
        oid: head,
        treeOid: headTree,
        treePaths,
      },
      refs: gitTips,
      candidates: [candidate],
      remotes: [],
      indexEntries,
      worktreeChanges: [
        {
          path: repoPath("tracked.txt"),
          originalPath: null,
          indexStatus: "unchanged",
          worktreeStatus: "modified",
        },
        {
          path: repoPath("untracked.txt"),
          originalPath: null,
          indexStatus: "unchanged",
          worktreeStatus: "added",
        },
      ],
      untrackedPaths: [repoPath("untracked.txt")],
      ignoredPaths: [],
      excludedUntracked: [],
      trackedSensitivePaths: [],
      leftBehind: [],
      jjCoverage: { classification: "none", headOids: [], operationId: null },
      fingerprints: {
        indexSha256: sha256(indexBytes),
        gitConfigSha256: sha256(configBytes),
        refsSha256: sha256(encoder.encode(refsRaw)),
        reflogsSha256: sha256(reflogBytes),
        odbListingSha256: sha256(reflogBytes),
        includedWorktreeSha256: sha256(encoder.encode(`${canonicalJson(snapshot.paths)}\n`)),
        jjStoreSha256: null,
        canonicalInputsSha256: sha256(encoder.encode("custody-verify fixture inputs")),
      },
      excludeFileSha256: null,
      dispositionsFileSha256: null,
    },
    snapshot,
    // Dirty capture: the review lives in snapshot.pathReview, so the clean
    // HEAD lane is explicitly empty (codec rejects the wrong lane).
    cleanHeadPathReview: null,
    baselines: {
      sourceRemoteTracking: [],
      destinationPreRefs: destTips,
      destinationPreRefsSha256: destinationRefsSha256(destTips),
      destinationWorktreeFingerprintSha256: sha256(destStatus),
      destinationIndexSha256: sha256(destIndexBytes),
      selectedBranch: "main",
      declaredRepo: "https://example.test/archive",
      headNotInRecordedBaseline: null,
      selectedTipsNotInDestination: null,
    },
    pins,
    bundle: sealed.sealed,
    checks: {
      sourceFingerprintRechecked: true,
      sourceOdbUnchanged: true,
      destinationWorktreeUnchanged: true,
      bundleClosureVerified: true,
    },
    unresolved: [
      {
        code: "consumer",
        subject: "/usr/local/bin/legacy-tool",
        reason: "legacy path consumers unverified",
      },
    ],
  };
  const receiptCommitOid = oid(
    await installReceiptBlob(dest, RECEIPT_REF, encodeReceipt(receipt)),
    "sha1",
  );

  return {
    root,
    source,
    dest,
    destReal,
    scratch,
    receipt,
    receiptCommitOid,
    receiptRef: RECEIPT_REF,
    pins,
    bundlePath: join(vaultRunDir, "source.bundle"),
    vaultRunDir,
  };
}

/** Fixture assertion helper: a missing pin means the fixture itself is broken. */
function mustFind(pins: readonly PinIntent[], pred: (pin: PinIntent) => boolean): PinIntent {
  const found = pins.find(pred);
  if (found === undefined) throw new Error("fixture is missing an expected pin lane");
  return found;
}

const verify = (a: Adoption, legacy: string | null = null): Promise<Verification> =>
  verifyAdoption({
    dest: a.dest,
    receiptRef: a.receiptRef,
    legacy,
    scratchRoot: a.scratch,
  });

const custodyError = async (promise: Promise<unknown>): Promise<CustodyError> => {
  try {
    await promise;
  } catch (error) {
    assert.ok(error instanceof CustodyError, `expected CustodyError, got ${String(error)}`);
    return error;
  }
  throw new Error("expected verifyAdoption to fail, but it succeeded");
};

test("real adoption verifies custody without the legacy checkout", async (t) => {
  const a = await adoption(t, "happy");
  const result = await verify(a);
  assert.deepEqual(result.custodyFailures, []);
  assert.equal(result.custodyVerified, true);
  assert.equal(result.receiptCommitOid, a.receiptCommitOid);
  assert.equal(result.receiptRef, a.receiptRef);
  assert.equal(result.destinationDrift, "unchanged");
  assert.equal(result.sourceDrift, "unknown");
  // jj evidence and receipt-carried retirement items are reported, never hidden.
  const codes = result.retirementUnresolved.map(({ code }) => code);
  assert.ok(codes.includes("jj-preflight-unavailable"));
  assert.ok(codes.includes("consumer"));
  // Stash, older-stash candidate, annotated tag, and snapshot lanes are all
  // proven by the same run: failures would list them otherwise.
  const observed = await readReceipt(a.dest, a.receiptRef);
  assert.equal(observed.receiptCommitOid, a.receiptCommitOid);
  assert.deepEqual(observed.receipt, a.receipt);
});

test("verification never mutates the destination", async (t) => {
  const a = await adoption(t, "immutable");
  const before = [
    (await treeLines(a.dest, ".git")).join("\n"),
    (await treeLines(join(a.dest, ".git"), null)).join("\n"),
  ];
  await verify(a);
  const after = [
    (await treeLines(a.dest, ".git")).join("\n"),
    (await treeLines(join(a.dest, ".git"), null)).join("\n"),
  ];
  assert.deepEqual(after, before);
});

test("bundle restore consumes the checked scratch copy, never reopens the vault path", async (t) => {
  const a = await adoption(t, "anchored-restore");
  const shimDir = join(a.root, "bin");
  await mkdir(shimDir);
  const observed = join(a.root, "bundle-argv");
  await writeFile(
    join(shimDir, "git"),
    `#!/bin/sh\ncase "$*" in\n  *'bundle list-heads'*) printf '%s\\n' "$*" >> '${observed}';;\nesac\nexec /usr/bin/git "$@"\n`,
    { mode: 0o755 },
  );
  const previous = process.env.PATH;
  process.env.PATH = `${shimDir}:${previous ?? ""}`;
  t.after(() => {
    process.env.PATH = previous;
  });
  assert.equal((await verify(a)).custodyVerified, true);
  const command = await readFile(observed, "utf8");
  assert.match(command, /verify-bundle-[^/]+\/source\.bundle/);
  assert.ok(!command.includes(a.bundlePath));
});

test("tampered and missing vault bundles fail custody distinctly", async (t) => {
  const tampered = await adoption(t, "tampered");
  const original = await readFile(tampered.bundlePath);
  await writeFile(tampered.bundlePath, Buffer.concat([original, Buffer.from("x")]));
  const tamperedResult = await verify(tampered);
  assert.equal(tamperedResult.custodyVerified, false);
  assert.ok(tamperedResult.custodyFailures.some(({ code }) => code === "bundle-checksum"));
  assert.ok(tamperedResult.custodyFailures.some(({ code }) => code === "bundle-restore"));

  const missing = await adoption(t, "missing-bundle");
  await rm(missing.bundlePath);
  const missingResult = await verify(missing);
  assert.equal(missingResult.custodyVerified, false);
  assert.ok(missingResult.custodyFailures.some(({ code }) => code === "bundle-unreadable"));
});

test("a bundle missing a pinned lane fails advertised-heads exactness", async (t) => {
  const a = await adoption(t, "partial-bundle");
  // Build a legitimate but incomplete bundle: only the HEAD lane.
  const holder = join(a.root, "partial");
  await mkdir(holder);
  const bare = join(holder, "partial.git");
  await run(holder, "init", "--quiet", "--bare", bare);
  const headPin = mustFind(a.pins, ({ sourceKind }) => sourceKind === "head");
  await run(
    bare,
    "-c",
    "gc.auto=0",
    "fetch",
    "--quiet",
    a.bundlePath,
    `+${headPin.destinationRef}:${headPin.destinationRef}`,
  );
  const partialBundle = join(holder, "partial.bundle");
  await run(bare, "bundle", "create", partialBundle, "--all");
  await writeFile(a.bundlePath, await readFile(partialBundle));
  const result = await verify(a);
  assert.equal(result.custodyVerified, false);
  const codes = result.custodyFailures.map(({ code }) => code);
  assert.ok(codes.includes("bundle-checksum"));
  assert.ok(codes.includes("bundle-restore"));
  // The shared restoration check names the exact head-set mismatch.
  assert.ok(
    result.custodyFailures.some(
      ({ code, reason }) => code === "bundle-restore" && /heads?/.test(reason),
    ),
  );
});

test("missing or repointed custody refs fail while the bundle stays proven", async (t) => {
  const absent = await adoption(t, "pin-absent");
  const branchPin = mustFind(absent.pins, ({ sourceKind }) => sourceKind === "branch");
  await run(absent.dest, "update-ref", "-d", branchPin.destinationRef);
  const absentResult = await verify(absent);
  assert.equal(absentResult.custodyVerified, false);
  assert.ok(absentResult.custodyFailures.some(({ code }) => code === "pin-ref-missing"));
  assert.ok(absentResult.custodyFailures.every(({ code }) => code !== "bundle-checksum"));

  const moved = await adoption(t, "pin-moved");
  const headPin = mustFind(moved.pins, ({ sourceKind }) => sourceKind === "head");
  const stashLane = mustFind(moved.pins, ({ sourceKind }) => sourceKind === "stash");
  const annotated = mustFind(
    moved.pins,
    ({ sourceKind, objectType }) => sourceKind === "tag" && objectType === "tag",
  );
  const olderStash = mustFind(moved.pins, ({ sourceKind }) => sourceKind === "reflog");
  // A different commit under the HEAD lane: OID mismatch only. Git itself
  // refuses tag objects under refs/heads/*, so the type mismatch is proven on
  // the custody lane, where any object type is addressable.
  await run(moved.dest, "update-ref", headPin.destinationRef, olderStash.destinationOid);
  await run(moved.dest, "update-ref", stashLane.destinationRef, annotated.destinationOid);
  const movedResult = await verify(moved);
  assert.equal(movedResult.custodyVerified, false);
  assert.ok(movedResult.custodyFailures.some(({ code }) => code === "pin-oid-mismatch"));
  assert.ok(movedResult.custodyFailures.some(({ code }) => code === "pin-type-mismatch"));
});

test("wrong-schema and noncanonical receipts fail parsing, not custody claims", async (t) => {
  const a = await adoption(t, "schema");
  const wrongSchema = JSON.stringify({ ...a.receipt, schema: "compfuzor.archive-adoption/v2" });
  await installReceiptBlob(a.dest, a.receiptRef, encoder.encode(wrongSchema));
  const wrong = await verify(a);
  assert.equal(wrong.custodyVerified, false);
  assert.ok(wrong.custodyFailures.some(({ code }) => code === "receipt-invalid"));
  assert.equal(wrong.destinationDrift, "unknown");

  const noncanonical = JSON.stringify(a.receipt);
  await installReceiptBlob(a.dest, a.receiptRef, encoder.encode(noncanonical));
  const loose = await verify(a);
  assert.equal(loose.custodyVerified, false);
  assert.ok(loose.custodyFailures.some(({ code }) => code === "receipt-invalid"));
});

test("a missing receipt ref is a hard verification failure", async (t) => {
  const a = await adoption(t, "no-receipt");
  await run(a.dest, "update-ref", "-d", a.receiptRef);
  const error = await custodyError(verify(a));
  assert.equal(error.code, "verification-failed");
  assert.ok(/does not exist/.test(error.message));
  const read = await custodyError(readReceipt(a.dest, a.receiptRef));
  assert.equal(read.code, "verification-failed");
});

test("vault symlinks are refused without following them", async (t) => {
  const archive = await adoption(t, "symlink-dir");
  const vaultArchive = dirname(archive.vaultRunDir);
  const outside = join(archive.root, "outside");
  await rename(vaultArchive, outside);
  await symlink(outside, vaultArchive);
  const result = await verify(archive);
  assert.equal(result.custodyVerified, false);
  assert.ok(result.custodyFailures.some(({ code }) => code === "vault-path-invalid"));

  const leaf = await adoption(t, "symlink-leaf");
  const realBundle = await readFile(leaf.bundlePath);
  await rm(leaf.bundlePath);
  await writeFile(join(leaf.root, "real-bundle"), realBundle, { mode: 0o600 });
  await symlink(join(leaf.root, "real-bundle"), leaf.bundlePath);
  const leafResult = await verify(leaf);
  assert.equal(leafResult.custodyVerified, false);
  assert.ok(leafResult.custodyFailures.some(({ code }) => code === "vault-path-invalid"));
});

test("a moved archive verifies via its moved vault, and a clone without one fails", async (t) => {
  const a = await adoption(t, "moved");
  const movedRoot = join(a.root, "moved");
  await mkdir(movedRoot);
  await rename(a.dest, join(movedRoot, "archive"));
  await rename(join(a.root, ".compfuzor-adoptions"), join(movedRoot, ".compfuzor-adoptions"));
  const movedDest = join(movedRoot, "archive");
  const result = await verifyAdoption({
    dest: movedDest,
    receiptRef: a.receiptRef,
    legacy: null,
    scratchRoot: a.scratch,
  });
  assert.deepEqual(result.custodyFailures, []);
  assert.equal(result.custodyVerified, true);
  assert.equal(result.destinationDrift, "unchanged");

  const clone = await adoption(t, "clone");
  await rm(join(clone.root, ".compfuzor-adoptions"), { recursive: true });
  const cloneResult = await verify(clone);
  assert.equal(cloneResult.custodyVerified, false);
  assert.ok(cloneResult.custodyFailures.some(({ code }) => code === "vault-path-invalid"));
});

test("removed and drifted legacy sources are diagnostics, never custody losses", async (t) => {
  const a = await adoption(t, "source-gone");
  await rm(a.source, { recursive: true });
  const absent = await verify(a, a.source);
  assert.equal(absent.custodyVerified, true);
  assert.equal(absent.sourceDrift, "absent");

  const drifted = await adoption(t, "source-drift");
  await writeFile(join(drifted.source, "tracked.txt"), "later edit\n");
  const changed = await verify(drifted, drifted.source);
  assert.equal(changed.custodyVerified, true);
  assert.equal(changed.sourceDrift, "changed");
  assert.equal(changed.destinationDrift, "unchanged");
});

test("source drift reads newline paths literally and hashes symlink text, not its target", async (t) => {
  const a = await adoption(t, "literal-source", { specialPaths: true });
  const unchanged = await verify(a, a.source);
  assert.equal(unchanged.custodyVerified, true);
  assert.equal(unchanged.sourceDrift, "unchanged");
  // Changing an external link target cannot alter the stored Git symlink blob.
  await writeFile(join(a.root, "outside-target"), "replaced outside contents\n");
  assert.equal((await verify(a, a.source)).sourceDrift, "unchanged");
  await writeFile(join(a.source, "line\nbreak"), "changed source bytes\n");
  assert.equal((await verify(a, a.source)).sourceDrift, "changed");
  await writeFile(join(a.source, "line\nbreak"), "newline filename\n");
  await rm(join(a.source, "nested"), { recursive: true });
  await symlink(a.root, join(a.source, "nested"));
  assert.equal((await verify(a, a.source)).sourceDrift, "changed");
});

test("clean apply with newline and symlink paths finishes post-install verification", async (t) => {
  const root = await area(t, "apply-special-paths");
  const source = join(root, "source");
  const dest = join(root, "destination");
  await run(root, "init", "--quiet", "--initial-branch=main", source);
  await writeFile(join(source, "line\nbreak"), "newline name\n");
  await symlink("line\nbreak", join(source, "link"));
  await run(source, ...identity, "add", "-A", ".");
  await run(source, ...identity, "commit", "--quiet", "-m", "base");
  await run(root, "clone", "--quiet", "--no-hardlinks", source, dest);
  await jj(["git", "init", "--colocate", "--quiet"], dest);
  const result = await Effect.runPromise(
    applyAdoption({
      legacy: source,
      dest,
      repo: source,
      branch: "main",
      label: "legacy",
      generation: "g0",
      excludeFrom: null,
      dispositions: null,
      pathReview: null,
    }),
  );
  assert.equal(result.verification.custodyVerified, true);
  assert.equal(result.verification.sourceDrift, "unchanged");
});

test("existing vault components must be private for writing and reading", async (t) => {
  const root = await area(t, "vault-privacy");
  const dest = join(root, "archive");
  await mkdir(dest);
  const destReal = await realpath(dest);
  const vault = join(root, VAULT_DIRNAME);
  await mkdir(vault, { mode: 0o777 });
  await chmod(vault, 0o777);
  const runId = vaultRunId();
  const denied = await custodyError(createVaultRun(destReal, runId));
  assert.match(denied.message, /owner-only/);
  const proven = await provenFacts(t, encoder.encode("private bundle\n"));
  const legacy = join(root, "legacy");
  await mkdir(legacy);
  const refusedSeal = await custodyError(
    sealBundle({
      destRealpath: destReal,
      legacyRealpath: await realpath(legacy),
      proven,
      intent: encoder.encode("{}\n"),
    }),
  );
  assert.match(refusedSeal.message, /owner-only/);
  assert.equal(await stat(join(vault, vaultArchiveId(destReal))).catch(() => null), null);
  await chmod(vault, 0o700);
  const archiveDir = join(vault, vaultArchiveId(destReal));
  await mkdir(archiveDir, { mode: 0o777 });
  await chmod(archiveDir, 0o777);
  const deniedArchive = await custodyError(createVaultRun(destReal, runId));
  assert.match(deniedArchive.message, /owner-only/);
  await chmod(archiveDir, 0o700);
  const run = await createVaultRun(destReal, runId);
  await sealVaultFile(run.bundlePath, encoder.encode("bundle bytes"));
  const receiptish = {
    identity: { destinationRealpath: destReal },
    bundle: {
      pathRelativeToDestinationParent: `${VAULT_DIRNAME}/${vaultArchiveId(destReal)}/${runId}/source.bundle`,
    },
  } as unknown as ReceiptV1;
  await chmod(run.bundlePath, 0o644);
  await assert.rejects(readVaultBundle(receiptish, destReal), VaultPathComponentError);
  await chmod(run.bundlePath, 0o600);
  await chmod(run.runDir, 0o777);
  await assert.rejects(readVaultBundle(receiptish, destReal), VaultPathComponentError);
  await chmod(run.runDir, 0o700);
  assert.deepEqual(
    (await readVaultBundle(receiptish, destReal)).bytes,
    Buffer.from("bundle bytes"),
  );
  // A non-root test process cannot manufacture a differently owned readable
  // inode; exercise uid refusal where chown is available without privileges.
  if (process.geteuid?.() === 0) {
    await chown(run.bundlePath, 65534, 65534);
    try {
      await assert.rejects(readVaultBundle(receiptish, destReal), VaultPathComponentError);
    } finally {
      await chown(run.bundlePath, 0, 0);
    }
  }
});

test("subsequent destination worktree drift is reported separately from custody", async (t) => {
  const a = await adoption(t, "dest-drift");
  await writeFile(join(a.dest, "archive-readme.md"), "archive\nlate operator edit\n");
  const result = await verify(a);
  assert.equal(result.custodyVerified, true);
  assert.deepEqual(result.custodyFailures, []);
  assert.equal(result.destinationDrift, "changed");
});

test("standalone verifier refuses destination status when a later clean filter could run", async (t) => {
  const a = await adoption(t, "late-filter", { attributedDest: true });
  const marker = join(a.root, "unsafe-filter-ran");
  await run(a.dest, "config", "filter.unsafe.clean", `sh -c 'touch "${marker}"; cat'`);
  // Equal-size edit forces Git status to inspect content instead of merely
  // detecting a stat-size difference. If status runs, the filter writes marker.
  await writeFile(join(a.dest, "archive-readme.md"), "altered\n");
  const odbBefore = await treeLines(join(a.dest, ".git", "objects"), null);
  const result = await verify(a);
  assert.equal(result.custodyVerified, true);
  assert.equal(result.destinationDrift, "unknown");
  assert.ok(
    result.retirementUnresolved.some(
      ({ code, reason }) =>
        code === "destination-drift-unavailable" && /filter\.unsafe\.clean/.test(reason),
    ),
  );
  assert.equal(await stat(marker).catch(() => null), null);
  assert.deepEqual(await treeLines(join(a.dest, ".git", "objects"), null), odbBefore);
});

test("jj-colocated destinations pass the read-only preflight without jj items", async (t) => {
  const a = await adoption(t, "jj-dest", { jjColocate: true });
  const opBefore = await jj(["op", "log", "--limit", "1", "--no-graph", "-T", "id"], a.dest, {
    readOnly: true,
  });
  const result = await verify(a);
  assert.deepEqual(result.custodyFailures, []);
  assert.equal(result.custodyVerified, true);
  assert.ok(!result.retirementUnresolved.some(({ code }) => code.startsWith("jj-")));
  // The pinned read-only query mode must not snapshot or import.
  const opAfter = await jj(["op", "log", "--limit", "1", "--no-graph", "-T", "id"], a.dest, {
    readOnly: true,
  });
  assert.equal(opAfter, opBefore);
});

// ---------------------------------------------------------------------------
// Durable vault writer (apply's seal path)
// ---------------------------------------------------------------------------

const mode = async (path: string): Promise<number> => (await stat(path)).mode & 0o777;

/** Minimal proven-bundle facts backed by real bytes on disk. */
async function provenFacts(
  t: { after: (hook: () => Promise<unknown>) => void },
  bytes: Uint8Array,
) {
  const holder = await area(t, "proven");
  const bundlePath = join(holder, "proven.bundle");
  await writeFile(bundlePath, bytes, { mode: 0o600 });
  return {
    bundlePath,
    bundleSha256: sha256(bytes),
    verifiedHeads: [
      {
        ref: refName(`refs/heads/harvest/legacy/g0/head/${"1".repeat(40)}`),
        oid: oid("1".repeat(40), "sha1"),
      },
    ],
    freshRestoreVerified: true as const,
  };
}

test("sealBundle installs an owner-only run, returns a receipt-ready record, and never overwrites", async (t) => {
  const root = await area(t, "writer");
  const dest = join(root, "archive");
  const legacy = join(root, "legacy");
  await mkdir(dest);
  await mkdir(legacy);
  const destReal = await realpath(dest);
  const proven = await provenFacts(t, encoder.encode("bundle bytes\n"));
  const intent = encoder.encode('{"schema":"compfuzor.archive-adoption-intent/v1"}\n');

  const { run, sealed } = await sealBundle({
    destRealpath: destReal,
    legacyRealpath: await realpath(legacy),
    proven,
    intent,
  });
  assert.equal(sealed.sha256, proven.bundleSha256);
  assert.deepEqual(sealed.verifiedHeads, proven.verifiedHeads);
  assert.equal(sealed.freshRestoreVerified, true);
  assert.equal(
    sealed.pathRelativeToDestinationParent,
    `${VAULT_DIRNAME}/${vaultArchiveId(destReal)}/${run.runId}/source.bundle`,
  );
  assert.match(run.runId, /^[0-9a-f]{32,}$/);
  // Owner-only structure: 0700 directories down the run, 0600 files inside.
  assert.equal(await mode(join(destReal, "..", VAULT_DIRNAME)), 0o700);
  assert.equal(await mode(run.archiveDir), 0o700);
  assert.equal(await mode(run.runDir), 0o700);
  assert.equal(await mode(run.bundlePath), 0o600);
  assert.equal(await mode(run.intentPath), 0o600);
  // The sealed bytes are exactly the proven bytes, and the resolver accepts
  // the recorded path under a receipt-shaped identity.
  assert.deepEqual(await readFile(run.bundlePath), Buffer.from("bundle bytes\n"));
  const receiptish = {
    identity: { destinationRealpath: destReal },
    bundle: { pathRelativeToDestinationParent: sealed.pathRelativeToDestinationParent },
  } as unknown as Parameters<typeof resolveVaultBundle>[0];
  assert.equal(await resolveVaultBundle(receiptish, destReal), run.bundlePath);

  // Runs are append-only: a second seal creates a distinct sibling run; a
  // checksum drift underfoot, a reused run id, and an existing target are all
  // refused — never overwritten.
  const again = await sealBundle({
    destRealpath: destReal,
    legacyRealpath: await realpath(legacy),
    proven,
    intent,
  });
  assert.notEqual(again.run.runId, run.runId);
  const before = await readFile(run.bundlePath);
  const drifted = await custodyError(
    sealBundle({
      destRealpath: destReal,
      legacyRealpath: await realpath(legacy),
      proven: { ...proven, bundleSha256: sha256(encoder.encode("tampered\n")) },
      intent,
    }),
  );
  assert.equal(drifted.code, "invalid-input");
  assert.equal(Buffer.compare(await readFile(run.bundlePath), before), 0);
  const reused = await custodyError(
    (async () => {
      const existing = await createVaultRun(destReal, run.runId);
      await sealVaultFile(existing.intentPath, intent);
    })(),
  );
  assert.equal(reused.code, "invalid-input");
});

test("sealBundle refuses vaults that would sit inside either checkout", async (t) => {
  const root = await area(t, "writer-roots");
  const legacy = join(root, "legacy");
  const destInside = join(legacy, "archive");
  await mkdir(legacy);
  await mkdir(destInside);
  const proven = await provenFacts(t, encoder.encode("bytes\n"));
  const inside = await custodyError(
    sealBundle({
      destRealpath: await realpath(destInside),
      legacyRealpath: await realpath(legacy),
      proven,
      intent: encoder.encode("{}\n"),
    }),
  );
  assert.equal(inside.code, "invalid-input");
  assert.ok(/legacy/.test(inside.message));
  // The refused attempt created nothing beside the legacy checkout.
  assert.equal(await stat(join(legacy, VAULT_DIRNAME)).catch(() => null), null);
  assert.match(vaultRunId(), /^[0-9a-f]{32,}$/);
});

test("readReceipt interruption kills the in-flight Git child before receipt lookup", async (t) => {
  const a = await adoption(t, "abort-read");
  const shimDir = join(a.root, "bin");
  await mkdir(shimDir);
  const marker = join(a.root, "blocked-pid");
  const calls = join(a.root, "git-calls");
  // Use an absolute executable outside our PATH shim.
  const realGit = "/usr/bin/git";
  assert.ok((await stat(realGit)).isFile());
  await writeFile(
    join(shimDir, "git"),
    `#!/bin/sh\nprintf '%s\\n' "$*" >> '${calls}'\ncase "$*" in\n  *'rev-parse --show-object-format'*) echo $$ > '${marker}'; exec sleep 30;;\nesac\nexec '${realGit}' "$@"\n`,
    { mode: 0o755 },
  );
  const previous = process.env.PATH;
  process.env.PATH = `${shimDir}:${previous ?? ""}`;
  t.after(() => {
    process.env.PATH = previous;
  });
  const controller = new AbortController();
  const pending = readReceipt(a.dest, a.receiptRef, { signal: controller.signal });
  let pid: number | undefined;
  for (let attempt = 0; attempt < 300; attempt++) {
    const found = await readFile(marker, "utf8").catch(() => null);
    if (found !== null) {
      pid = Number(found.trim());
      break;
    }
    await delay(10);
  }
  assert.ok(pid, "fake Git must have entered long subprocess");
  controller.abort(new DOMException("cancel read", "AbortError"));
  await assert.rejects(
    pending,
    (error: unknown) => error instanceof DOMException && error.name === "AbortError",
  );
  assert.throws(() => process.kill(pid!, 0), { code: "ESRCH" });
  assert.ok(!(await readFile(calls, "utf8")).includes("for-each-ref"));
  await rm(marker);
  await writeFile(calls, "");
  const verifyController = new AbortController();
  const verification = verifyAdoption(
    {
      dest: a.dest,
      receiptRef: a.receiptRef,
      legacy: null,
      scratchRoot: a.scratch,
    },
    { signal: verifyController.signal },
  );
  let verifyPid: number | undefined;
  for (let attempt = 0; attempt < 300; attempt++) {
    const found = await readFile(marker, "utf8").catch(() => null);
    if (found !== null) {
      verifyPid = Number(found.trim());
      break;
    }
    await delay(10);
  }
  assert.ok(verifyPid, "verification must enter long Git subprocess");
  verifyController.abort(new DOMException("cancel verification", "AbortError"));
  await assert.rejects(verification, { name: "AbortError" });
  assert.throws(() => process.kill(verifyPid!, 0), { code: "ESRCH" });
  assert.ok(!(await readFile(calls, "utf8")).includes("for-each-ref"));
});

test("aborted vault seal cannot claim a complete bundle", async (t) => {
  const root = await area(t, "abort-seal");
  const dest = join(root, "archive");
  const legacy = join(root, "legacy");
  await mkdir(dest);
  await mkdir(legacy);
  const proven = await provenFacts(t, encoder.encode("bundle bytes\n"));
  const controller = new AbortController();
  // Aborting immediately must leave no sealed record and no vault run.
  controller.abort(new DOMException("cancel seal", "AbortError"));
  await assert.rejects(
    sealBundle(
      {
        destRealpath: await realpath(dest),
        legacyRealpath: await realpath(legacy),
        proven,
        intent: encoder.encode("{}\n"),
      },
      { signal: controller.signal },
    ),
    { name: "AbortError" },
  );
  assert.equal(await stat(join(root, VAULT_DIRNAME)).catch(() => null), null);
  // A cancellation between the intent and bundle install retains the run as
  // diagnosis; the caller never gets a receipt-ready sealed record.
  const run = await createVaultRun(await realpath(dest), vaultRunId());
  await sealVaultFile(run.intentPath, encoder.encode("{}\n"));
  const mid = new AbortController();
  mid.abort(new DOMException("cancel continuation", "AbortError"));
  await assert.rejects(
    sealVaultFile(run.bundlePath, encoder.encode("bundle bytes\n"), { signal: mid.signal }),
    { name: "AbortError" },
  );
  assert.equal(await stat(run.bundlePath).catch(() => null), null);
  assert.ok((await stat(run.intentPath)).isFile());
});
