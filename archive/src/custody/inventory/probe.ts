/**
 * Read-only source and destination evidence collection for custody planning.
 *
 * Every Git invocation goes through `gitRead` from `archive/src/repository/
 * git.ts`: argv arrays, explicit cwd, optional locks disabled, lazy fetches
 * and replace refs refused, host/system config excluded, maintenance off.
 * Exit statuses are checked explicitly — a nonzero exit is a probe result,
 * not an exception. Nothing here stages, commits, exports, repairs, fetches
 * or writes in either repository; filesystem access is read-only.
 *
 * Inspection failures become named blockers plus a null inventory category
 * (never a fabricated empty list), per the PlanV1 observed-inventory
 * contract. Unsupported Git variants (linked worktrees, shallow, promisor,
 * sparse, alternates, filters, unknown extensions) are named blockers, not
 * silent exclusions.
 */
import { Effect, Result } from "effect";
import { open, readFile, readdir, lstat, realpath, stat } from "node:fs/promises";
import { join, relative, resolve } from "node:path";
import { gitRead } from "../../repository/git.ts";
import { oid as oidOf, destinationRefsSha256, sha256 } from "../codec.ts";
import { CustodyError } from "../errors.ts";
import type {
  Candidate,
  GitObjectFormat,
  GitTip,
  Issue,
  Oid,
  PathEntry,
  RepoPath,
  SourceInventory,
} from "../model.ts";
import { jjDirectory } from "./jj.ts";
import {
  parseBoolean,
  parseConfigPairs,
  parseForEachRef,
  parseFsck,
  parseHashObjectLines,
  parseLsFilesStage,
  parseLsTree,
  parseReflogShow,
  parseRemoteUrls,
  parseStatusV2,
  strictUtf8,
} from "./decode.ts";

/** Bounds keep the plan honest: past them the category becomes a named blocker. */
export const BOUNDS = {
  reflogEntries: 8192,
  untracked: 4096,
  ignoredListed: 512,
  odbFiles: 16384,
  jjFiles: 8192,
  manifestUntracked: 2048,
  hashBatch: 128,
} as const;

export interface RawEvidence {
  readonly refs: Uint8Array | null;
  readonly reflogs: Uint8Array | null;
  readonly status: Uint8Array | null;
}

type Observed = { -readonly [K in keyof SourceInventory]: SourceInventory[K] | null };

export interface SourceProbe {
  readonly source: string;
  readonly gitDir: string | null;
  readonly objectFormat: GitObjectFormat | null;
  readonly observed: Observed;
  readonly blockers: readonly Issue[];
  readonly warnings: readonly Issue[];
  readonly leftBehind: readonly Issue[];
  readonly retirementUnresolved: readonly Issue[];
  readonly raw: RawEvidence;
  /** Peeled ref tips plus HEAD; the ancestry ceiling for jj coverage. */
  readonly selectedTipOids: readonly Oid[];
  /** Provisional included path/mode/blob manifest (HEAD tree + tracked/untracked input). */
  readonly includedManifest: readonly PathEntry[] | null;
  /** Inputs for fingerprints, null when any component was uninspectable. */
  readonly fingerprintFiles: {
    readonly indexBytes: Uint8Array;
    readonly configBytes: Uint8Array;
    readonly odbListing: string | null;
    readonly jjStore: string | null;
  } | null;
  /** Dirty tracked/untracked state present: private staging would be required. */
  readonly dirty: boolean;
}

/** Lift a throwing decode into the Effect error channel as a CustodyError. */
const sync = <A>(decode: () => A): Effect.Effect<A, CustodyError> =>
  Effect.try({
    try: decode,
    catch: (error) =>
      error instanceof CustodyError ? error : new CustodyError("inspection-failed", String(error)),
  });

/**
 * Resolve a path inside the repository the same way Git does (`--git-path`),
 * so linked-worktree and similar layouts read the right file instead of
 * assuming `$GIT_DIR/<name>`. Null makes callers fall back to the plain join.
 */
function gitPath(real: string, name: string): Effect.Effect<string | null, CustodyError> {
  return Effect.gen(function* () {
    const out = yield* git(["rev-parse", "--git-path", name], real);
    if (out.exitCode !== 0) return null;
    const text = yield* sync(() => strictUtf8(out.stdout, `git path ${name}`).trim());
    return text === "" ? null : resolve(real, text);
  });
}

const isHex2 = (name: string): boolean => /^[0-9a-f]{2}$/.test(name);

async function isDirectory(path: string): Promise<boolean> {
  const info = await stat(path, { throwIfNoEntry: false });
  return info !== undefined && info.isDirectory();
}

async function isFile(path: string): Promise<boolean> {
  // Node's fs/promises.lstat does not honor throwIfNoEntry (verified on
  // Node 26: it rejects with ENOENT where stat resolves undefined).
  try {
    return (await lstat(path)).isFile();
  } catch {
    return false;
  }
}

const fs = <A>(operation: () => Promise<A>, what: string): Effect.Effect<A, CustodyError> =>
  Effect.tryPromise({
    try: operation,
    catch: (error) =>
      new CustodyError(
        "inspection-failed",
        `${what}: ${error instanceof Error ? error.message : String(error)}`,
      ),
  });

/** Run a read-only git command; nonzero exits are returned, not thrown. */
function git(
  args: readonly string[],
  cwd: string,
): Effect.Effect<{ stdout: Uint8Array; stderr: Uint8Array; exitCode: number }, CustodyError> {
  return gitRead(args, { cwd }).pipe(
    Effect.mapError(
      (error) => new CustodyError("inspection-failed", `git ${args[0]}: ${error.message}`),
    ),
  );
}

/** Stdout bytes when the command exited zero, otherwise null. */
function gitZero(
  args: readonly string[],
  cwd: string,
): Effect.Effect<Uint8Array | null, CustodyError> {
  return git(args, cwd).pipe(
    Effect.map((result) => (result.exitCode === 0 ? result.stdout : null)),
  );
}

/** Exit-0 predicate for an ancestry/existence probe. */
function gitOk(args: readonly string[], cwd: string): Effect.Effect<boolean, never> {
  return git(args, cwd).pipe(
    Effect.map((result) => result.exitCode === 0),
    Effect.catch(() => Effect.succeed(false)),
  );
}

async function walkFiles(root: string, cap: number, what: string): Promise<string[]> {
  const found: string[] = [];
  const visit = async (dir: string): Promise<void> => {
    const entries = await readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) await visit(full);
      else if (entry.isFile()) {
        found.push(relative(root, full));
        if (found.length > cap)
          throw new CustodyError("inspection-failed", `${what} listing exceeds ${cap} files`);
      }
    }
  };
  await visit(root);
  return found.sort();
}

/** Loose and packed object inventory: relative paths and sizes, no contents. */
async function odbListing(objectsDir: string): Promise<string> {
  const lines: string[] = [];
  const entries = await readdir(objectsDir, { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    if (entry.name === "info") continue;
    if (!isHex2(entry.name) && entry.name !== "pack") continue;
    const files = await walkFiles(join(objectsDir, entry.name), BOUNDS.odbFiles, "object database");
    for (const file of files) {
      const info = await lstat(join(objectsDir, entry.name, file));
      lines.push(`objects/${join(entry.name, file)}\t${info.size}`);
    }
  }
  if (lines.length > BOUNDS.odbFiles)
    throw new CustodyError("inspection-failed", "object database exceeds bound");
  lines.sort();
  return lines.join("\n");
}

/** Per-file content digest of the jj store: proves jj state unchanged across probes. */
async function jjStoreListing(source: string): Promise<string> {
  const root = join(source, ".jj");
  const files = await walkFiles(root, BOUNDS.jjFiles, "jj store");
  const lines: string[] = [];
  for (const file of files) lines.push(`${file}\t${sha256(await readFile(join(root, file)))}`);
  lines.sort();
  return lines.join("\n");
}

const CREDENTIAL_BASENAME =
  /^(\.env(\..+)?|[^/]*\.env|id_(rsa|ed25519|ecdsa)(\.pub)?|[^/]*\.(pem|key|kdbx|p12|pfx)|credentials(\..+)?|secrets?\..+)$/;
const SENSITIVE_COMPONENTS = new Set([".ssh", ".gnupg", ".aws", ".kube"]);
const RUNTIME_COMPONENTS = new Set([".beads", ".data", ".cache"]);

/** Name/class only — never contents, never credential values. */
function sensitiveClass(path: string): string | null {
  const parts = path.split("/");
  const base = parts[parts.length - 1] ?? "";
  if (parts.some((part) => SENSITIVE_COMPONENTS.has(part)) || CREDENTIAL_BASENAME.test(base))
    return "credential-like";
  if (parts.some((part) => RUNTIME_COMPONENTS.has(part))) return "runtime-state";
  return null;
}

const hasInternals = (path: string): boolean =>
  path.split("/").some((part) => part === ".git" || part === ".jj");

/** Canonical LFS pointer header; matching this prefix identifies a pointer. */
const LFS_POINTER_PREFIX = "version https://git-lfs.github.com/spec/v1\n";
/** Bounded header read: pointer files are ~130 bytes, never megabytes. */
const LFS_PROBE_BYTES = LFS_POINTER_PREFIX.length;

/**
 * Detect LFS pointer files among the files the synthetic tree would stage:
 * the current index/worktree state of tracked paths plus selected untracked
 * paths, never ignored files. Only the fixed-size header prefix is read and
 * only the match/no-match outcome is recorded — file contents are never
 * emitted. Scope is the current snapshot input, not the whole history:
 * pointers deeper in history surface when their blobs enter the manifest.
 */
async function lfsPointers(root: string, paths: readonly RepoPath[]): Promise<readonly RepoPath[]> {
  const found: RepoPath[] = [];
  const header = Buffer.from(LFS_POINTER_PREFIX, "latin1");
  for (const path of paths) {
    const handle = await open(join(root, path), "r").catch(() => null);
    if (handle === null) continue; // deleted or unreadable: not a pointer
    try {
      const buffer = Buffer.alloc(LFS_PROBE_BYTES);
      const { bytesRead } = await handle.read(buffer, 0, LFS_PROBE_BYTES, 0);
      if (
        buffer.subarray(0, bytesRead).equals(header.subarray(0, bytesRead)) &&
        bytesRead === LFS_PROBE_BYTES
      )
        found.push(path);
    } finally {
      await handle.close();
    }
  }
  return found;
}

function parseNulPaths(bytes: Uint8Array): RepoPath[] {
  const parts = strictUtf8(bytes, "path list").split("\0");
  if (parts.length > 0 && parts[parts.length - 1] === "") parts.pop();
  return parts.map((part) => part as RepoPath);
}

export interface ProbeOptions {
  readonly excludeFrom: string | null;
  readonly dispositions: ReadonlyMap<
    string,
    { disposition: "pin" | "not-required"; reason: string | null }
  > | null;
}

/**
 * Collect the complete read-only source inventory with admission decisions.
 * Categories that cannot be faithfully represented stay null with a named
 * blocker. `dispositions` maps candidate identities (`kind:oid`) to operator
 * decisions; unknown identities are rejected by the caller, not here.
 */
export function probeSource(
  source: string,
  options: ProbeOptions,
): Effect.Effect<SourceProbe, CustodyError> {
  return Effect.gen(function* () {
    const blockers: Issue[] = [];
    const warnings: Issue[] = [];
    const leftBehind: Issue[] = [];
    const retirement: Issue[] = [];
    const observed: Observed = {
      objectFormat: null,
      sourceGitCommonDir: null,
      head: null,
      refs: null,
      candidates: null,
      remotes: null,
      indexEntries: null,
      worktreeChanges: null,
      untrackedPaths: null,
      ignoredPaths: null,
      excludedUntracked: null,
      trackedSensitivePaths: null,
      leftBehind: null,
      jjCoverage: null,
      fingerprints: null,
      excludeFileSha256: null,
      dispositionsFileSha256: null,
    };
    const raw: { refs: Uint8Array | null; reflogs: Uint8Array | null; status: Uint8Array | null } =
      {
        refs: null,
        reflogs: null,
        status: null,
      };

    /**
     * Decode one inventory category: a decode failure becomes a named blocker
     * and a null result, so unrepresentable bytes block the plan instead of
     * failing the probe or fabricating an empty list.
     */
    const category = <A>(
      code: string,
      effect: Effect.Effect<A, CustodyError>,
    ): Effect.Effect<A | null, never> =>
      Effect.result(effect).pipe(
        Effect.map((result) => {
          if (Result.isFailure(result)) {
            blockers.push({ code, subject: null, reason: result.failure.message });
            return null;
          }
          return result.success;
        }),
      );

    const dir = yield* fs(() => isDirectory(source), "inspect source path");
    if (!dir) {
      blockers.push({
        code: "source-not-directory",
        subject: source,
        reason: "adoption source must be an existing directory",
      });
      return {
        source,
        gitDir: null,
        objectFormat: null,
        observed,
        blockers,
        warnings,
        leftBehind,
        retirementUnresolved: retirement,
        raw,
        selectedTipOids: [],
        includedManifest: null,
        fingerprintFiles: null,
        dirty: false,
      };
    }
    const real = yield* fs(() => realpath(source), "resolve source path");
    const earlyReturn = (): SourceProbe => ({
      source: real,
      gitDir,
      objectFormat: format,
      observed,
      blockers,
      warnings,
      leftBehind,
      retirementUnresolved: retirement,
      raw,
      selectedTipOids: [],
      includedManifest: null,
      fingerprintFiles: null,
      dirty: false,
    });
    let gitDir: string | null = null;
    let format: GitObjectFormat | null = null;
    leftBehind.push({
      code: "source-repository-metadata",
      subject: join(real, ".git"),
      reason:
        "the source repository directory itself is never captured; only selected Git objects are",
    });

    if (yield* fs(() => isFile(join(real, ".git")), "inspect .git entry"))
      blockers.push({
        code: "source-gitfile-linked-worktree",
        subject: join(real, ".git"),
        reason: "`.git` is a file: linked worktrees are unsupported in v1",
      });

    const gitDirOut = yield* git(["rev-parse", "--absolute-git-dir"], real);
    if (gitDirOut.exitCode !== 0) {
      blockers.push({
        code: "source-not-git-repository",
        subject: real,
        reason: "not inside a Git work tree",
      });
      return earlyReturn();
    }
    const gitDirDecoded = yield* category(
      "source-gitdir-unrepresentable",
      sync(() => strictUtf8(gitDirOut.stdout, "git dir").trim()),
    );
    if (gitDirDecoded === null) return earlyReturn();
    gitDir = gitDirDecoded;
    observed.sourceGitCommonDir = gitDir;

    const commonOut = yield* git(["rev-parse", "--git-common-dir"], real);
    if (commonOut.exitCode === 0) {
      // `--git-common-dir` may be relative (`.git`); resolve against the
      // worktree before comparing. Note `--path-absolute` must not be used:
      // rev-parse echoes unconsumed flags, corrupting the output.
      const common = yield* category(
        "source-gitdir-unrepresentable",
        sync(() => strictUtf8(commonOut.stdout, "git common dir").trim()),
      );
      if (common !== null && resolve(real, common) !== gitDir)
        blockers.push({
          code: "source-linked-worktree",
          subject: gitDir,
          reason: `git dir ${gitDir} differs from common dir ${resolve(real, common)}: linked worktree`,
        });
    }

    const bareOut = yield* gitZero(["rev-parse", "--is-bare-repository"], real);
    if (bareOut !== null) {
      const bare = yield* category(
        "source-inspection-failed",
        sync(() => parseBoolean(bareOut, "bare flag")),
      );
      if (bare === true)
        blockers.push({
          code: "source-bare",
          subject: gitDir,
          reason: "bare repositories have no worktree to adopt",
        });
    }

    const formatOut = yield* gitZero(["rev-parse", "--show-object-format"], real);
    if (formatOut === null) {
      blockers.push({
        code: "source-format-unknown",
        subject: gitDir,
        reason: "object format could not be determined",
      });
      return earlyReturn();
    }
    const formatText = yield* category(
      "source-format-unrepresentable",
      sync(() => strictUtf8(formatOut, "object format").trim()),
    );
    if (formatText === null || (formatText !== "sha1" && formatText !== "sha256")) {
      if (formatText !== null)
        blockers.push({
          code: "source-format-unsupported",
          subject: gitDir,
          reason: `unknown object format ${formatText}`,
        });
      return earlyReturn();
    }
    format = formatText;
    observed.objectFormat = format;

    // --- unsupported-variant gates (each names itself; probing continues) ---
    const alternatesPath =
      (yield* gitPath(real, "objects/info/alternates")) ??
      join(gitDir, "objects", "info", "alternates");
    const alternates = yield* fs(
      () => readFile(alternatesPath).catch(() => null),
      "read alternates",
    );
    if (alternates !== null && alternates.length > 0)
      blockers.push({
        code: "source-alternates",
        subject: alternatesPath,
        reason: "alternate object directories make closure unprovable in v1",
      });

    const shallowOut = yield* gitZero(["rev-parse", "--is-shallow-repository"], real);
    if (shallowOut !== null) {
      const shallow = yield* category(
        "source-inspection-failed",
        sync(() => parseBoolean(shallowOut, "shallow flag")),
      );
      if (shallow === true)
        blockers.push({
          code: "source-shallow",
          subject: gitDir,
          reason: "shallow history is not complete custody",
        });
    }

    const extensionsOut = yield* gitZero(["config", "--get-regexp", "^extensions\\."], real);
    if (extensionsOut !== null) {
      const pairs = yield* category(
        "source-inspection-failed",
        sync(() => parseConfigPairs(extensionsOut)),
      );
      for (const { key } of pairs ?? [])
        if (key !== "extensions.objectformat")
          blockers.push({
            code: "source-unsupported-extension",
            subject: key,
            reason: `Git extension ${key} is not supported by v1 custody`,
          });
    }

    const promisorOut = yield* gitZero(
      [
        "config",
        "--get-regexp",
        "^remote\\..*\\.(promisor|partialclonefilter)$|^extensions\\.partialclone$",
      ],
      real,
    );
    if (promisorOut !== null && promisorOut.length > 0)
      blockers.push({
        code: "source-partial-clone",
        subject: gitDir,
        reason: "promisor/partial clone configuration implies fetching v1 refuses",
      });

    const sparseMain = yield* gitZero(["config", "--get", "core.sparseCheckout"], real);
    const sparseCone = yield* gitZero(["config", "--get", "core.sparseCheckoutCone"], real);
    const sparseList = yield* git(["sparse-checkout", "list"], real);
    const sparseMainOn =
      sparseMain === null
        ? false
        : (yield* category(
            "source-inspection-failed",
            sync(() => parseBoolean(sparseMain, "sparse config")),
          )) === true;
    const sparseConeOn =
      sparseCone === null
        ? false
        : (yield* category(
            "source-inspection-failed",
            sync(() => parseBoolean(sparseCone, "sparse cone")),
          )) === true;
    if (sparseMainOn || sparseConeOn || sparseList.exitCode === 0)
      blockers.push({
        code: "source-sparse-checkout",
        subject: gitDir,
        reason: "sparse checkouts do not hold the full worktree",
      });

    const filtersOut = yield* gitZero(["config", "--get-regexp", "^filter\\."], real);
    if (filtersOut !== null && filtersOut.length > 0) {
      const filterPairs = yield* category(
        "source-inspection-failed",
        sync(() => parseConfigPairs(filtersOut)),
      );
      const names = (filterPairs ?? []).map(({ key }) => key);
      blockers.push({
        code: "source-filter-configured",
        subject: gitDir,
        reason: `clean/smudge filters cannot be faithfully staged in v1: ${names.join(", ")}`,
      });
    }

    // --- HEAD ---
    let symbolicRef: string | null = null;
    let headOid: Oid | null = null;
    const symref = yield* git(["symbolic-ref", "-q", "HEAD"], real);
    if (symref.exitCode === 0) {
      symbolicRef = yield* category(
        "source-head-unrepresentable",
        sync(() => strictUtf8(symref.stdout, "HEAD symbolic ref").trim()),
      );
    } else if (symref.exitCode === 1) {
      warnings.push({
        code: "detached-head",
        subject: null,
        reason: "HEAD is detached; the exact commit will be pinned separately",
      });
    } else {
      blockers.push({
        code: "source-head-unknowable",
        subject: gitDir,
        reason: "HEAD could not be inspected",
      });
    }
    const headVerify = yield* git(["rev-parse", "--verify", "HEAD"], real);
    if (headVerify.exitCode === 0)
      headOid = yield* category(
        "source-head-unrepresentable",
        sync(() => oidOf(strictUtf8(headVerify.stdout, "HEAD oid").trim(), format)),
      );
    else
      blockers.push({
        code: "source-unborn-head",
        subject: symbolicRef,
        reason: "unborn HEAD: no commit exists to take custody of",
      });

    let treePaths: readonly PathEntry[] | null = null;
    if (headOid !== null) {
      const treeVerify = yield* git(["rev-parse", "--verify", "HEAD^{tree}"], real);
      const treeOut = yield* gitZero(["ls-tree", "-r", "-z", "HEAD"], real);
      if (treeVerify.exitCode === 0 && treeOut !== null) {
        treePaths = yield* category(
          "source-head-tree-unrepresentable",
          sync(() => parseLsTree(treeOut, format)),
        );
        const treeOid = yield* category(
          "source-head-unrepresentable",
          sync(() => oidOf(strictUtf8(treeVerify.stdout, "HEAD tree").trim(), format)),
        );
        for (const entry of treePaths ?? []) {
          if (entry.mode === "160000")
            blockers.push({
              code: "source-submodule-gitlink",
              subject: entry.path,
              reason: "gitlink entries require separate submodule custody design",
            });
          if (hasInternals(entry.path))
            blockers.push({
              code: "source-tracked-internals",
              subject: entry.path,
              reason: "tracked .git/.jj path components cannot be adopted; classify explicitly",
            });
        }
        if (treePaths !== null && treeOid !== null)
          observed.head = {
            symbolicRef: symbolicRef as SourceInventory["head"]["symbolicRef"],
            oid: headOid,
            treeOid,
            treePaths,
          };
      } else {
        blockers.push({
          code: "source-head-tree-unknowable",
          subject: gitDir,
          reason: "HEAD tree manifest could not be listed",
        });
      }
    }

    // --- refs ---
    const refsOut = yield* git(
      ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(*objectname)%00"],
      real,
    );
    let refs: readonly GitTip[] | null = null;
    if (refsOut.exitCode === 0) {
      raw.refs = refsOut.stdout;
      refs = yield* category(
        "source-refs-unrepresentable",
        sync(() => parseForEachRef(refsOut.stdout, format)),
      );
      observed.refs = refs;
      if (refs?.some(({ name }) => name.startsWith("refs/jj/")))
        warnings.push({
          code: "jj-internal-refs",
          subject: null,
          reason: "refs/jj/* keep refs present; they are inventoried but are jj-internal",
        });
    } else {
      blockers.push({
        code: "source-refs-unknowable",
        subject: gitDir,
        reason: "for-each-ref failed",
      });
    }

    // --- reflogs ---
    const reflogOut = yield* git(["reflog", "show", "--all", "--format=%H%x00%gD%x00"], real);
    let reflogEntries: ReturnType<typeof parseReflogShow> | null = null;
    if (reflogOut.exitCode === 0) {
      raw.reflogs = reflogOut.stdout;
      const decoded = yield* category(
        "source-reflogs-unrepresentable",
        sync(() => parseReflogShow(reflogOut.stdout, format)),
      );
      if (decoded !== null && decoded.length > BOUNDS.reflogEntries) {
        blockers.push({
          code: "source-reflogs-unbounded",
          subject: gitDir,
          reason: `reflog entries exceed ${BOUNDS.reflogEntries}`,
        });
        reflogEntries = null;
      } else {
        reflogEntries = decoded;
      }
    } else {
      blockers.push({
        code: "source-reflogs-unknowable",
        subject: gitDir,
        reason: "reflog show --all failed",
      });
    }

    // --- index ---
    const indexPath = (yield* gitPath(real, "index")) ?? join(gitDir, "index");
    const indexBytes = yield* fs(() => readFile(indexPath).catch(() => null), "read index");
    const stageOut = yield* gitZero(["ls-files", "--stage", "-z"], real);
    if (stageOut !== null) {
      const indexEntries = yield* category(
        "source-index-unrepresentable",
        sync(() => parseLsFilesStage(stageOut, format)),
      );
      observed.indexEntries = indexEntries;
      for (const entry of indexEntries ?? []) {
        if (entry.stage !== 0)
          blockers.push({
            code: "source-unmerged-index",
            subject: entry.path,
            reason: `unmerged index entry at stage ${entry.stage} blocks synthetic staging`,
          });
        if (entry.mode === "160000")
          blockers.push({
            code: "source-submodule-gitlink",
            subject: entry.path,
            reason: "gitlink index entries require separate submodule custody design",
          });
      }
    } else {
      blockers.push({
        code: "source-index-unknowable",
        subject: gitDir,
        reason: "ls-files --stage failed",
      });
    }

    // --- status, untracked, ignored ---
    const statusOut = yield* git(["status", "--porcelain=v2", "-z", "--untracked-files=all"], real);
    let statusParsed: ReturnType<typeof parseStatusV2> | null = null;
    if (statusOut.exitCode === 0) {
      raw.status = statusOut.stdout;
      statusParsed = yield* category(
        "source-status-unrepresentable",
        sync(() => parseStatusV2(statusOut.stdout)),
      );
    } else {
      blockers.push({
        code: "source-status-unknowable",
        subject: gitDir,
        reason: "status --porcelain=v2 failed",
      });
    }
    if (statusParsed !== null) observed.worktreeChanges = statusParsed.changes;

    const untrackedOut = yield* gitZero(["ls-files", "--others", "--exclude-standard", "-z"], real);
    const selectedOut =
      options.excludeFrom === null
        ? null
        : yield* gitZero(
            [
              "ls-files",
              "--others",
              "--exclude-standard",
              "-z",
              "--exclude-from",
              options.excludeFrom,
            ],
            real,
          );
    let untracked: readonly RepoPath[] | null = null;
    let excludedUntracked: readonly RepoPath[] = [];
    if (untrackedOut !== null) {
      const listed = yield* category(
        "source-untracked-unrepresentable",
        sync(() => parseNulPaths(untrackedOut)),
      );
      if (listed === null || listed.length > BOUNDS.untracked) {
        if (listed !== null)
          blockers.push({
            code: "source-untracked-unbounded",
            subject: gitDir,
            reason: `untracked paths exceed ${BOUNDS.untracked}`,
          });
      } else {
        untracked = listed.filter((path) => {
          if (!hasInternals(path)) return true;
          leftBehind.push({
            code: "untracked-repository-internals",
            subject: path,
            reason: "untracked .git/.jj internals are never staged into the synthetic tree",
          });
          return false;
        });
        observed.untrackedPaths = untracked;
        if (options.excludeFrom === null) {
          observed.excludedUntracked = [];
        } else if (selectedOut !== null) {
          const selected = yield* category(
            "source-untracked-unrepresentable",
            sync(() => parseNulPaths(selectedOut)),
          );
          if (selected === null) {
            blockers.push({
              code: "source-excluded-unknowable",
              subject: gitDir,
              reason: "--exclude-from selection could not be represented",
            });
          } else {
            const selectedSet = new Set(selected);
            excludedUntracked = untracked.filter((path) => !selectedSet.has(path));
            observed.excludedUntracked = excludedUntracked;
          }
        } else {
          blockers.push({
            code: "source-excluded-unknowable",
            subject: gitDir,
            reason: "--exclude-from selection query failed",
          });
        }
      }
    } else {
      blockers.push({
        code: "source-untracked-unknowable",
        subject: gitDir,
        reason: "ls-files --others failed",
      });
    }

    const ignoredOut = yield* gitZero(
      ["ls-files", "--others", "--ignored", "--exclude-standard", "-z"],
      real,
    );
    if (ignoredOut !== null) {
      const ignoredAll = yield* category(
        "source-ignored-unrepresentable",
        sync(() => parseNulPaths(ignoredOut)),
      );
      const listed = (ignoredAll ?? []).slice(0, BOUNDS.ignoredListed);
      observed.ignoredPaths = listed;
      for (const path of listed)
        leftBehind.push({
          code: "ignored-runtime-state",
          subject: path,
          reason: "ignored files are left behind, never staged; runtime state is a retirement item",
        });
      if ((ignoredAll?.length ?? 0) > listed.length)
        warnings.push({
          code: "ignored-paths-capped",
          subject: null,
          reason: `${(ignoredAll?.length ?? 0) - listed.length} further ignored paths not listed (bound ${BOUNDS.ignoredListed})`,
        });
      retirement.push({
        code: "ignored-runtime-state",
        subject: null,
        reason: `${ignoredAll?.length ?? 0} ignored path(s) remain with the source; DB/WAL consistency is not established`,
      });
    } else {
      blockers.push({
        code: "source-ignored-unknowable",
        subject: gitDir,
        reason: "ignored listing failed",
      });
    }

    // --- LFS pointers among snapshot input (current index/worktree scope) ---
    if (observed.indexEntries !== null && untracked !== null && statusParsed !== null) {
      const deleted = new Set(
        statusParsed.changes
          .filter(
            ({ indexStatus, worktreeStatus }) =>
              indexStatus === "deleted" || worktreeStatus === "deleted",
          )
          .flatMap(({ path, originalPath }) =>
            originalPath === null ? [path] : [path, originalPath],
          ),
      );
      const staged = [
        ...new Set([...observed.indexEntries.map(({ path }) => path), ...untracked]),
      ].filter((path) => !deleted.has(path));
      if (staged.length > BOUNDS.untracked) {
        blockers.push({
          code: "source-lfs-probe-unbounded",
          subject: gitDir,
          reason: `snapshot input exceeds the LFS pointer probe bound ${BOUNDS.untracked}`,
        });
      } else {
        const pointers = yield* Effect.result(
          fs(() => lfsPointers(real, staged), "probe LFS pointers"),
        );
        if (Result.isFailure(pointers))
          blockers.push({
            code: "source-lfs-probe-failed",
            subject: gitDir,
            reason: pointers.failure.message,
          });
        else
          for (const path of pointers.success)
            blockers.push({
              code: "source-lfs-pointer",
              subject: path,
              reason:
                "LFS pointer file in snapshot input: v1 custody cannot take custody of LFS payloads from pointers",
            });
      }
    }

    // --- tracked sensitive paths (names/classes only) ---    const sensitive: Issue[] = [];
    const seenSensitive = new Set<string>();
    for (const entry of [...(treePaths ?? []), ...(observed.indexEntries ?? [])]) {
      if (seenSensitive.has(entry.path)) continue;
      seenSensitive.add(entry.path);
      const classification = sensitiveClass(entry.path);
      if (classification !== null)
        sensitive.push({
          code: "tracked-sensitive-path",
          subject: entry.path,
          reason: `${classification}: flagged for privacy review; custody does not authorize publication`,
        });
    }
    observed.trackedSensitivePaths = sensitive;

    // --- candidates: fsck dangling tips + uncovered reflog entries ---
    let candidates: readonly Candidate[] = [];
    let candidatesKnowable = true;
    const fsckRun = yield* git(["fsck", "--no-reflogs", "--unreachable"], real);
    const report = yield* sync(() => parseFsck(fsckRun.stdout, fsckRun.stderr, format));
    if (fsckRun.exitCode !== 0 && fsckRun.stdout.length === 0) {
      blockers.push({
        code: "source-fsck-unknowable",
        subject: gitDir,
        reason: "fsck failed without output",
      });
      candidatesKnowable = false;
    } else {
      if (report.corruption.length > 0)
        blockers.push({
          code: "source-object-corruption",
          subject: gitDir,
          reason: `fsck reported: ${report.corruption.slice(0, 3).join("; ")}`,
        });
      candidates = report.candidates.map((candidate) => ({
        kind: "dangling" as const,
        oid: candidate.oid,
        objectType: candidate.objectType,
        provenance: ["fsck --no-reflogs --unreachable"],
        disposition:
          candidate.objectType === "commit" || candidate.objectType === "tag"
            ? ("unclassified" as const)
            : ("not-required" as const),
        reason:
          candidate.objectType === "commit" || candidate.objectType === "tag"
            ? null
            : "unreferenced noncommit object; inventoried only, not presumed wanted",
      }));
    }

    if (reflogEntries !== null && refs !== null) {
      const tipOids = new Set<string>([
        ...refs.map((ref) => ref.oid),
        ...refs.map((ref) => ref.peeledOid).filter((oid): oid is Oid => oid !== null),
      ]);
      if (headOid !== null) tipOids.add(headOid);
      const byOid = new Map<string, string[]>();
      for (const entry of reflogEntries) {
        if (tipOids.has(entry.oid)) continue;
        byOid.set(entry.oid, [...(byOid.get(entry.oid) ?? []), entry.selector]);
      }
      const stashTip = refs.find(({ name }) => name === "refs/stash")?.oid ?? null;
      const reflogCandidates: Candidate[] = [];
      for (const [oidText, selectors] of byOid) {
        const stashSelectors = selectors.filter((selector) => selector.startsWith("refs/stash@{"));
        if (stashSelectors.length > 0 && oidText !== stashTip) {
          reflogCandidates.push({
            kind: "stash-older",
            oid: oidText as Oid,
            objectType: "commit",
            provenance: stashSelectors,
            disposition: "pin",
            reason: "older stash entry: pinned by default per stash custody policy",
          });
          continue;
        }
        let covered = false;
        for (const tip of tipOids) {
          if (yield* gitOk(["merge-base", "--is-ancestor", oidText, tip], real)) {
            covered = true;
            break;
          }
        }
        if (!covered)
          reflogCandidates.push({
            kind: "reflog",
            oid: oidText as Oid,
            objectType: "commit",
            provenance: selectors,
            disposition: "unclassified",
            reason: null,
          });
      }
      // Merge with fsck dangling candidates sharing an OID: the reflog
      // identity (stash-older pin, reflog candidate) is the more specific
      // classification and wins over the generic dangling label; fsck
      // provenance is retained alongside the reflog selectors.
      const candidatesByOid = new Map(candidates.map((candidate) => [candidate.oid, candidate]));
      const merged: Candidate[] = [...candidates];
      for (const candidate of reflogCandidates) {
        const existing = candidatesByOid.get(candidate.oid);
        if (existing !== undefined && existing.kind === "dangling") {
          const index = merged.indexOf(existing);
          merged[index] = {
            ...candidate,
            provenance: [...candidate.provenance, ...existing.provenance],
          };
        } else {
          merged.push(candidate);
        }
      }
      candidates = merged;
    } else if (candidatesKnowable) {
      blockers.push({
        code: "source-reflog-candidates-unknowable",
        subject: gitDir,
        reason: "reflog or ref inventory unavailable; candidates cannot be classified",
      });
      candidatesKnowable = false;
    }

    if (options.dispositions !== null) {
      const dispositions = options.dispositions;
      candidates = candidates.map((candidate) => {
        const decision = dispositions.get(`${candidate.kind}:${candidate.oid}`);
        return decision === undefined
          ? candidate
          : { ...candidate, disposition: decision.disposition, reason: decision.reason };
      });
    }
    const unclassified = candidates.filter(({ disposition }) => disposition === "unclassified");
    if (unclassified.length > 0)
      blockers.push({
        code: "candidates-unclassified",
        subject: null,
        reason: `dangling/reflog work lacks dispositions: ${unclassified
          .map(({ kind, oid }) => `${kind}:${oid}`)
          .join(", ")
          .slice(0, 400)}`,
      });
    if (candidatesKnowable) observed.candidates = candidates;

    // --- remotes ---
    const remotesOut = yield* git(["config", "--get-regexp", "^remote\\..*\\.url$"], real);
    if (remotesOut.exitCode === 0)
      observed.remotes = yield* category(
        "source-remotes-unrepresentable",
        sync(() => parseRemoteUrls(remotesOut.stdout)),
      );
    else if (remotesOut.exitCode === 1) observed.remotes = [];
    else
      blockers.push({
        code: "source-remotes-unknowable",
        subject: gitDir,
        reason: "remote url configuration unreadable",
      });

    // --- dirty detection and provisional included manifest ---
    const stagedChanges = (statusParsed?.changes ?? []).filter(
      ({ indexStatus }) => indexStatus !== "unchanged",
    );
    const unstagedChanges = (statusParsed?.changes ?? []).filter(
      ({ worktreeStatus }) => worktreeStatus !== "unchanged",
    );
    const dirty =
      stagedChanges.length > 0 || unstagedChanges.length > 0 || (untracked?.length ?? 0) > 0;
    if (stagedChanges.length > 0 && unstagedChanges.length > 0)
      warnings.push({
        code: "staged-vs-unstaged",
        subject: null,
        reason:
          "both staged and unstaged changes exist; a single synthetic tree cannot preserve the split",
      });

    let includedManifest: readonly PathEntry[] | null = null;
    if (treePaths !== null && statusParsed !== null && untracked !== null) {
      const manifest = new Map<string, PathEntry>();
      for (const entry of treePaths) manifest.set(entry.path, entry);
      const hashable: RepoPath[] = [];
      for (const change of statusParsed.changes) {
        if (change.indexStatus === "deleted" || change.worktreeStatus === "deleted") {
          manifest.delete(change.path);
          continue;
        }
        if (change.originalPath !== null) manifest.delete(change.originalPath);
        hashable.push(change.path);
      }
      const selectedUntracked = untracked.filter((path) => !excludedUntracked.includes(path));
      if (selectedUntracked.length > BOUNDS.manifestUntracked) {
        blockers.push({
          code: "source-manifest-unbounded",
          subject: gitDir,
          reason: `included untracked paths exceed ${BOUNDS.manifestUntracked}`,
        });
      } else {
        for (const path of selectedUntracked) hashable.push(path);
        const oidByPath = new Map<RepoPath, Oid>();
        let hashOk = true;
        for (let i = 0; i < hashable.length && hashOk; i += BOUNDS.hashBatch) {
          const batch = hashable.slice(i, i + BOUNDS.hashBatch);
          const hashed = yield* gitZero(["hash-object", "--no-filters", "--", ...batch], real);
          if (hashed === null) {
            hashOk = false;
            break;
          }
          const oids = yield* category(
            "source-manifest-unrepresentable",
            sync(() => parseHashObjectLines(hashed, format, batch.length)),
          );
          if (oids === null) {
            hashOk = false;
            break;
          }
          batch.forEach((path, index) => oidByPath.set(path, oids[index]));
        }
        if (hashOk) {
          for (const [path, oid] of oidByPath) {
            const info = yield* fs(() => lstat(join(real, path)), `stat ${path}`);
            const mode: PathEntry["mode"] = info.isSymbolicLink()
              ? "120000"
              : (info.mode & 0o111) !== 0
                ? "100755"
                : "100644";
            manifest.set(path, { path, mode, blobOid: oid });
          }
          includedManifest = [...manifest.values()].sort((a, b) =>
            a.path < b.path ? -1 : a.path > b.path ? 1 : 0,
          );
        } else {
          blockers.push({
            code: "source-manifest-unknowable",
            subject: gitDir,
            reason: "hash-object failed; included manifest cannot be computed",
          });
        }
      }
    }

    // --- fingerprint inputs ---
    let fingerprintFiles: SourceProbe["fingerprintFiles"] = null;
    const configPath = (yield* gitPath(real, "config")) ?? join(gitDir, "config");
    const objectsDir = (yield* gitPath(real, "objects")) ?? join(gitDir, "objects");
    const configBytes = yield* fs(() => readFile(configPath), "read config");
    const odb = yield* Effect.result(fs(() => odbListing(objectsDir), "list object database"));
    const hasJj = yield* fs(() => jjDirectory(real), "check .jj");
    const jj: Result.Result<string | null, CustodyError> = hasJj
      ? yield* Effect.result(fs(() => jjStoreListing(real), "fingerprint jj store"))
      : Result.succeed(null);
    if (Result.isSuccess(odb)) {
      if (indexBytes !== null) {
        fingerprintFiles = {
          indexBytes,
          configBytes,
          odbListing: odb.success,
          jjStore: Result.isSuccess(jj) ? jj.success : null,
        };
      } else {
        blockers.push({
          code: "source-index-unknowable",
          subject: join(gitDir, "index"),
          reason: "index bytes unreadable; fingerprints impossible",
        });
      }
    } else {
      blockers.push({
        code: "source-odb-unknowable",
        subject: gitDir,
        reason: `object database listing failed: ${odb.failure.message}`,
      });
    }
    if (Result.isFailure(jj))
      blockers.push({
        code: "source-jj-store-unknowable",
        subject: join(real, ".jj"),
        reason: `jj store fingerprint failed: ${jj.failure.message}`,
      });

    // --- selected tips for jj coverage and counts ---
    // refs/jj/* are jj's internal keep refs, not user-facing Git tips:
    // counting them as coverage would silently admit jj-only revisions, so
    // they stay inventoried (and later pinnable) but outside the ceiling.
    const selectedTipOids: Oid[] = [];
    const seenTips = new Set<string>();
    const addTip = (tip: string): void => {
      if (seenTips.has(tip)) return;
      seenTips.add(tip);
      selectedTipOids.push(tip as Oid);
    };
    if (headOid !== null) addTip(headOid);
    for (const ref of refs ?? []) {
      if (ref.name.startsWith("refs/jj/")) continue;
      addTip(ref.peeledOid ?? ref.oid);
    }

    observed.leftBehind = leftBehind;
    return {
      source: real,
      gitDir,
      objectFormat: format,
      observed,
      blockers,
      warnings,
      leftBehind,
      retirementUnresolved: retirement,
      raw,
      selectedTipOids,
      includedManifest,
      fingerprintFiles,
      dirty,
    };
  }).pipe(
    Effect.catchDefect((defect) =>
      Effect.fail(
        defect instanceof CustodyError
          ? defect
          : new CustodyError("inspection-failed", `unexpected defect: ${String(defect)}`),
      ),
    ),
  );
}

export interface DestinationProbe {
  readonly exists: boolean;
  readonly realpath: string | null;
  readonly blockers: readonly Issue[];
  readonly warnings: readonly Issue[];
  readonly gitDir: string | null;
  readonly objectFormat: GitObjectFormat | null;
  readonly preRefs: readonly GitTip[] | null;
  readonly preRefsSha256: string | null;
  readonly statusSha256: string | null;
  readonly indexSha256: string | null;
}

/** Read-only destination checks: clean worktree, declared origin, exact pre-state. */
export function probeDestination(
  dest: string,
  declaredRepo: string,
  sourceFormat: GitObjectFormat | null,
): Effect.Effect<DestinationProbe, CustodyError> {
  return Effect.gen(function* () {
    const blockers: Issue[] = [];
    const warnings: Issue[] = [];
    const category = <A>(
      code: string,
      effect: Effect.Effect<A, CustodyError>,
    ): Effect.Effect<A | null, never> =>
      Effect.result(effect).pipe(
        Effect.map((result) => {
          if (Result.isFailure(result)) {
            blockers.push({ code, subject: null, reason: result.failure.message });
            return null;
          }
          return result.success;
        }),
      );
    const partial = (): DestinationProbe => ({
      exists: true,
      realpath: real,
      blockers,
      warnings,
      gitDir: null,
      objectFormat: null,
      preRefs: null,
      preRefsSha256: null,
      statusSha256: null,
      indexSha256: null,
    });
    const missing = (): DestinationProbe => ({
      exists: false,
      realpath: null,
      blockers: [
        {
          code: "destination-missing",
          subject: dest,
          reason:
            "destination does not exist; creation awaits the safe-clone slice after plan approval",
        },
      ],
      warnings,
      gitDir: null,
      objectFormat: null,
      preRefs: null,
      preRefsSha256: null,
      statusSha256: null,
      indexSha256: null,
    });
    const real = yield* fs(() => realpath(dest).catch(() => null), "resolve destination");
    if (real === null || !(yield* fs(() => isDirectory(real), "inspect destination")))
      return missing();

    if (yield* fs(() => isFile(join(real, ".git")), "inspect dest .git"))
      blockers.push({
        code: "destination-gitfile-linked-worktree",
        subject: real,
        reason: "destination .git is a file",
      });

    const gitDirOut = yield* git(["rev-parse", "--absolute-git-dir"], real);
    if (gitDirOut.exitCode !== 0) {
      blockers.push({
        code: "destination-not-git-repository",
        subject: real,
        reason: "no Git repository at destination",
      });
      return {
        exists: true,
        realpath: real,
        blockers,
        warnings,
        gitDir: null,
        objectFormat: null,
        preRefs: null,
        preRefsSha256: null,
        statusSha256: null,
        indexSha256: null,
      };
    }
    const gitDirDecoded = yield* category(
      "destination-inspection-failed",
      sync(() => strictUtf8(gitDirOut.stdout, "dest git dir").trim()),
    );
    if (gitDirDecoded === null) return partial();
    const gitDir = gitDirDecoded;
    const commonOut = yield* git(["rev-parse", "--git-common-dir"], real);
    if (commonOut.exitCode === 0) {
      const common = yield* category(
        "destination-inspection-failed",
        sync(() => strictUtf8(commonOut.stdout, "dest common dir").trim()),
      );
      if (common !== null && resolve(real, common) !== gitDir)
        blockers.push({
          code: "destination-linked-worktree",
          subject: gitDir,
          reason: "destination is a linked worktree",
        });
    }
    const bareOut = yield* gitZero(["rev-parse", "--is-bare-repository"], real);
    if (bareOut !== null) {
      const bare = yield* category(
        "destination-inspection-failed",
        sync(() => parseBoolean(bareOut, "dest bare flag")),
      );
      if (bare === true)
        blockers.push({
          code: "destination-bare",
          subject: gitDir,
          reason: "bare destination lacks the required worktree",
        });
    }
    if (!(yield* fs(() => jjDirectory(real), "check dest .jj")))
      blockers.push({
        code: "destination-jj-missing",
        subject: real,
        reason: "destination must be a jj-colocated archive",
      });

    const destAlternatesPath =
      (yield* gitPath(real, "objects/info/alternates")) ??
      join(gitDir, "objects", "info", "alternates");
    const alternates = yield* fs(
      () => readFile(destAlternatesPath).catch(() => null),
      "read dest alternates",
    );
    if (alternates !== null && alternates.length > 0)
      blockers.push({
        code: "destination-alternates",
        subject: gitDir,
        reason: "destination alternates weaken object custody",
      });

    const shallowOut = yield* gitZero(["rev-parse", "--is-shallow-repository"], real);
    if (shallowOut !== null) {
      const shallow = yield* category(
        "destination-inspection-failed",
        sync(() => parseBoolean(shallowOut, "dest shallow flag")),
      );
      if (shallow === true)
        blockers.push({
          code: "destination-shallow",
          subject: gitDir,
          reason: "shallow destination cannot hold full custody",
        });
    }

    const extensionsOut = yield* gitZero(["config", "--get-regexp", "^extensions\\."], real);
    if (extensionsOut !== null) {
      const pairs = yield* category(
        "destination-inspection-failed",
        sync(() => parseConfigPairs(extensionsOut)),
      );
      for (const { key } of pairs ?? [])
        if (key !== "extensions.objectformat")
          blockers.push({
            code: "destination-unsupported-extension",
            subject: key,
            reason: `Git extension ${key} unsupported at destination`,
          });
    }

    let objectFormat: GitObjectFormat | null = null;
    const formatOut = yield* gitZero(["rev-parse", "--show-object-format"], real);
    if (formatOut !== null) {
      const text = yield* category(
        "destination-inspection-failed",
        sync(() => strictUtf8(formatOut, "dest object format").trim()),
      );
      if (text === "sha1" || text === "sha256") {
        objectFormat = text;
        if (sourceFormat !== null && sourceFormat !== text)
          blockers.push({
            code: "destination-object-format-mismatch",
            subject: real,
            reason: `source ${sourceFormat} versus destination ${text}`,
          });
      }
    }

    const originOut = yield* git(["config", "--get", "remote.origin.url"], real);
    if (originOut.exitCode === 0) {
      const origin = yield* category(
        "destination-inspection-failed",
        sync(() => strictUtf8(originOut.stdout, "origin url").trim()),
      );
      if (origin !== null && origin !== declaredRepo)
        blockers.push({
          code: "destination-remote-mismatch",
          subject: "origin",
          reason: `declared ${declaredRepo} but destination origin is ${origin}`,
        });
    } else {
      blockers.push({
        code: "destination-origin-missing",
        subject: real,
        reason: "destination has no origin remote url",
      });
    }

    const statusOut = yield* git(["status", "--porcelain=v2", "-z", "--untracked-files=all"], real);
    let statusSha256: string | null = null;
    if (statusOut.exitCode === 0) {
      statusSha256 = sha256(statusOut.stdout);
      const parsed = yield* category(
        "destination-status-unrepresentable",
        sync(() => parseStatusV2(statusOut.stdout)),
      );
      if (parsed !== null && parsed.changes.length > 0)
        blockers.push({
          code: "destination-worktree-dirty",
          subject: real,
          reason: `destination has ${parsed.changes.length} tracked change(s); busy checkouts block adoption`,
        });
      if (parsed !== null && parsed.untracked.length > 0)
        warnings.push({
          code: "destination-untracked",
          subject: real,
          reason: `${parsed.untracked.length} untracked destination path(s) recorded`,
        });
    } else {
      blockers.push({
        code: "destination-status-unknowable",
        subject: real,
        reason: "destination status failed",
      });
    }

    const refsOut = yield* git(
      ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(*objectname)%00"],
      real,
    );
    let preRefs: readonly GitTip[] | null = null;
    let preRefsSha256: string | null = null;
    if (refsOut.exitCode === 0 && objectFormat !== null) {
      preRefs = yield* category(
        "destination-refs-unrepresentable",
        sync(() => parseForEachRef(refsOut.stdout, objectFormat)),
      );
      if (preRefs !== null) preRefsSha256 = destinationRefsSha256(preRefs);
    } else if (objectFormat !== null) {
      blockers.push({
        code: "destination-refs-unknowable",
        subject: real,
        reason: "destination for-each-ref failed",
      });
    }

    const destIndexPath = (yield* gitPath(real, "index")) ?? join(gitDir, "index");
    const indexBytes = yield* fs(
      () => readFile(destIndexPath).catch(() => null),
      "read dest index",
    );

    return {
      exists: true,
      realpath: real,
      blockers,
      warnings,
      gitDir,
      objectFormat,
      preRefs,
      preRefsSha256,
      statusSha256,
      indexSha256: indexBytes === null ? null : sha256(indexBytes),
    };
  }).pipe(
    Effect.catchDefect((defect) =>
      Effect.fail(
        defect instanceof CustodyError
          ? defect
          : new CustodyError("inspection-failed", `unexpected defect: ${String(defect)}`),
      ),
    ),
  );
}
