/**
 * Read-only jj inspection seam for custody.
 *
 * Every jj invocation goes through {@link jj} in query mode (`readOnly`,
 * historically `pinned`), which injects `--ignore-working-copy --at-op=@`:
 * per jj 0.45.1 help and the repository/jj.ts fixture evidence, that neither
 * snapshots the working copy nor imports colocated Git refs, and pinning to
 * the current operation head means divergent operations are never merged —
 * so a query can observe jj's view without writing anything. Only read-only
 * subcommands are ever called here; the argv below is the complete
 * allowlist. Fixture tests prove the jj store and Git side stay identical.
 *
 * A second hazard this seam closes: `jj` walks up parent directories when the
 * cwd is not itself a jj repository, which would silently query (or worse)
 * an enclosing repo. `.jj` must exist as a directory before any invocation.
 */
import { Effect, Result } from "effect";
import { stat } from "node:fs/promises";
import { join } from "node:path";
import { gitRead } from "../../repository/git.ts";
import { jj, JjError, REF_TEMPLATE } from "../../repository/jj.ts";
import { CustodyError } from "../errors.ts";
import type { Issue, JjCoverage, Oid } from "../model.ts";

/** Visible-head bound: beyond this a repo is not plannable by v1 inventory. */
export const MAX_VISIBLE_HEADS = 512;

const pinned = (args: string[], repo: string) =>
  // Interruption contract: when the jj wrapper gains its optional execution
  // AbortSignal, this callback MUST forward Effect.tryPromise's callback
  // signal into the jj read options so an interrupted plan cannot leave a
  // detached child behind. Until that API lands there is nothing to forward.
  Effect.tryPromise({
    try: () => jj(args, repo, { readOnly: true }),
    catch: (error): CustodyError =>
      error instanceof JjError
        ? new CustodyError("inspection-failed", `jj ${error.args.join(" ")}: ${error.detail}`)
        : new CustodyError("inspection-failed", `jj query failed: ${String(error)}`),
  });

export async function jjDirectory(repo: string): Promise<boolean> {
  const info = await stat(join(repo, ".jj"), { throwIfNoEntry: false });
  return info !== undefined && info.isDirectory();
}

/** Ghost commits: jj heads whose Git objects are missing from the store. */
function ghosts(detail: string): string[] {
  return [
    ...new Set(
      [...detail.matchAll(/Object ([0-9a-f]{40,64}) of type commit not found/gi)].map((m) => m[1]),
    ),
  ];
}

/** Pinned, read-only visible-head enumeration for a jj repository. */
function visibleHeads(repo: string): Effect.Effect<string[], CustodyError> {
  return Effect.gen(function* () {
    const output = yield* pinned(
      ["log", "-r", "visible_heads()", "--no-graph", "-T", 'commit_id ++ "\\n"'],
      repo,
    );
    const heads = output.split("\n").filter((line) => line !== "");
    if (heads.length > MAX_VISIBLE_HEADS)
      return yield* Effect.fail(
        new CustodyError("inspection-failed", `jj visible heads exceed ${MAX_VISIBLE_HEADS}`),
      );
    return heads;
  });
}

export interface JjSourceView {
  readonly classification: JjCoverage["classification"];
  readonly headOids: readonly Oid[];
  readonly uncoveredOids: readonly Oid[];
  readonly conflictedHeadOids: readonly Oid[];
  readonly operationId: string | null;
  readonly workingCopyOid: Oid | null;
  /** `true` when @ is diff-empty versus its first parent; `null` = unknown. */
  readonly workingCopyEmpty: boolean | null;
  /** `true` when @ carries a description (an intentional jj commit); `null` = unknown. */
  readonly workingCopyDescribed: boolean | null;
  readonly failure: Issue | null;
}

const blockedView = (reason: string): JjSourceView => ({
  classification: "blocked",
  headOids: [],
  uncoveredOids: [],
  conflictedHeadOids: [],
  operationId: null,
  workingCopyOid: null,
  workingCopyEmpty: null,
  workingCopyDescribed: null,
  failure: { code: "jj-inspection-failed", subject: null, reason },
});

/** Exit code 0 for a read-only `gitRead` invocation; false on any failure. */
function exitOk(result: { readonly exitCode: number }): boolean {
  return result.exitCode === 0;
}

/**
 * Classify jj state of a source checkout against the currently selected Git
 * tips (full ref tips plus HEAD, peeled). Heads jj knows about that current
 * Git tips do not cover — including commits absent from the Git ODB — are
 * reported uncovered, never silently inferred away. The working-copy commit
 * is exempt only while it is diff-empty *and* undescribed: the pristine
 * colocated working copy carries no Git-representable work, while a
 * described or content-bearing @ is intentional jj-only work and blocks.
 */
export function sourceJjView(
  repo: string,
  selectedGitTips: readonly Oid[],
  format: "sha1" | "sha256",
): Effect.Effect<JjSourceView, never> {
  const inspect = Effect.gen(function* () {
    const operation = yield* pinned(
      ["op", "log", "--limit", "1", "--no-graph", "-T", 'id ++ "\\n"'],
      repo,
    );
    const wcOutput = yield* pinned(
      [
        "log",
        "-r",
        "@",
        "--no-graph",
        "-T",
        'commit_id ++ " " ++ empty ++ " " ++ description.len()',
      ],
      repo,
    );
    const heads = (yield* visibleHeads(repo)) as Oid[];
    const conflicts = yield* pinned(
      ["log", "-r", "visible_heads() & conflicts()", "--no-graph", "-T", 'commit_id ++ "\\n"'],
      repo,
    );
    const [wcOidText, wcEmptyText, wcDescText] = wcOutput.split(" ");
    const oidPattern = format === "sha1" ? /^[0-9a-f]{40}$/ : /^[0-9a-f]{64}$/;
    const workingCopyOid = oidPattern.test(wcOidText) ? (wcOidText as Oid) : null;
    const workingCopyEmpty = wcEmptyText === "true" ? true : wcEmptyText === "false" ? false : null;
    const workingCopyDescribed =
      wcDescText !== undefined && /^\d+$/.test(wcDescText) ? Number(wcDescText) > 0 : null;

    const uncovered: Oid[] = [];
    for (const head of heads) {
      if (head === workingCopyOid && workingCopyEmpty === true && workingCopyDescribed === false)
        continue;
      const known = yield* gitRead(["cat-file", "-e", `${head}^{commit}`], { cwd: repo }).pipe(
        Effect.map(exitOk),
        Effect.catch(() => Effect.succeed(false)),
      );
      if (!known) {
        uncovered.push(head);
        continue;
      }
      let covered = false;
      for (const tip of selectedGitTips) {
        const verdict = yield* gitRead(["merge-base", "--is-ancestor", head, tip], {
          cwd: repo,
        }).pipe(
          Effect.map(exitOk),
          Effect.catch(() => Effect.succeed(false)),
        );
        if (verdict) {
          covered = true;
          break;
        }
      }
      if (!covered) uncovered.push(head);
    }

    return {
      classification: uncovered.length === 0 ? "git-covered" : "blocked",
      headOids: heads,
      uncoveredOids: uncovered,
      conflictedHeadOids: conflicts.split("\n").filter((line) => line !== "") as Oid[],
      operationId: operation,
      workingCopyOid,
      workingCopyEmpty,
      workingCopyDescribed,
      failure: null,
    } satisfies JjSourceView;
  });

  return Effect.gen(function* () {
    const present = yield* Effect.result(
      Effect.tryPromise({
        try: () => jjDirectory(repo),
        catch: (error) =>
          new CustodyError("inspection-failed", `jj presence check: ${String(error)}`),
      }),
    );
    if (Result.isFailure(present))
      return blockedView(`jj presence check: ${present.failure.message}`);
    if (!present.success)
      return {
        classification: "none",
        headOids: [],
        uncoveredOids: [],
        conflictedHeadOids: [],
        operationId: null,
        workingCopyOid: null,
        workingCopyEmpty: null,
        workingCopyDescribed: null,
        failure: null,
      } satisfies JjSourceView;
    const result = yield* Effect.result(inspect);
    return Result.isSuccess(result)
      ? result.success
      : blockedView(`${result.failure.code}: ${result.failure.message}`);
  });
}

export interface DestJjView {
  readonly ghostOids: readonly string[];
  readonly conflictedBookmarks: readonly string[];
  readonly failure: Issue | null;
}

/**
 * Destination jj preflight, pinned and read-only: visible heads must resolve
 * (ghost commits are reported, not healed) and no bookmark may be conflicted.
 */
export function destinationJjView(dest: string): Effect.Effect<DestJjView, never> {
  return Effect.gen(function* () {
    const heads = yield* Effect.result(
      pinned(["log", "-r", "visible_heads()", "--no-graph", "-T", 'commit_id ++ "\\n"'], dest),
    );
    if (Result.isFailure(heads)) {
      const found = ghosts(heads.failure.message);
      if (found.length > 0)
        return {
          ghostOids: found,
          conflictedBookmarks: [],
          failure: {
            code: "destination-jj-ghost-heads",
            subject: null,
            reason: `jj heads missing from Git object store: ${found.join(", ")}`,
          },
        } satisfies DestJjView;
      return {
        ghostOids: [],
        conflictedBookmarks: [],
        failure: {
          code: "destination-jj-inspection-failed",
          subject: dest,
          reason: `${heads.failure.code}: ${heads.failure.message}`,
        },
      } satisfies DestJjView;
    }
    const bookmarks = yield* Effect.result(
      pinned(["bookmark", "list", "--all-remotes", "-T", REF_TEMPLATE], dest),
    );
    if (Result.isFailure(bookmarks))
      return {
        ghostOids: [],
        conflictedBookmarks: [],
        failure: {
          code: "destination-jj-inspection-failed",
          subject: dest,
          reason: `bookmark list: ${bookmarks.failure.message}`,
        },
      } satisfies DestJjView;
    const conflicted: string[] = [];
    for (const line of bookmarks.success
      .split("\n")
      .filter((line: string): boolean => line !== "")) {
      const parts = line.split("\t");
      if (parts.length === 4 && parts[2] === "conflict")
        conflicted.push(parts[0] + (parts[1] === "-" ? "" : `@${parts[1]}`));
    }
    return {
      ghostOids: [],
      conflictedBookmarks: conflicted,
      failure:
        conflicted.length > 0
          ? {
              code: "destination-jj-conflicts",
              subject: null,
              reason: `conflicted bookmarks: ${conflicted.join(", ")}`,
            }
          : null,
    } satisfies DestJjView;
  });
}
