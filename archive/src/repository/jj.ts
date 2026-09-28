/**
 * The only shell boundary for jj; never interpolates user arguments into a
 * shell. jj runs through `effect/process` `ChildProcess` spawned by the
 * `ChildProcessSpawner` (`NodeServices.layer`), so scope and cancellation
 * belong to the spawner; this module only collects output and checks the
 * exit code. The library boundary stays Promise-based for the repository,
 * recovery, and custody callers.
 *
 * Cancellation: a Promise cannot be cancelled from outside, but every jj
 * spawn here accepts an optional {@link ExecutionOptions} signal. The signal
 * is forwarded to `Effect.runPromise`, which interrupts the fiber that owns
 * the spawn scope — the spawner's scope finalizer then SIGTERMs (and waits
 * on) the child's process group. The CLI feeds its main-fiber interruption
 * signal in this way (see cli/failure.ts), so SIGINT/SIGTERM on the process
 * kills in-flight children instead of orphaning them.
 *
 * The child inherits the parent environment untouched. jj is
 * operator-facing tooling: `JJ_CONFIG`, `JJ_EDITOR`, a `PATH` override, and
 * the rest of the operator's jj setup must keep working. Unlike the raw-git
 * adapter (see git.ts, which strips `GIT_*` because it executes real git),
 * jj cannot be redirected through inherited Git variables: it locates the
 * repository by `.jj` discovery from the explicit `cwd` and opens the
 * colocated Git backend at the path recorded in the repo, ignoring
 * `GIT_DIR`/`GIT_WORK_TREE` and `GIT_CONFIG_*` injection (verified against
 * jj 0.45.1 on colocated fixtures: decoy `GIT_DIR` neither rerouted reads
 * like `log` nor writes like `git remote add`, and `GIT_CONFIG_GLOBAL`
 * identity injection left jj authors untouched). Routing is therefore
 * always the explicit `cwd`, and there is deliberately no env sanitizer
 * here that could silently break operator jj configuration.
 */
import { stat } from "node:fs/promises";
import { NodeServices } from "@effect/platform-node";
import { Effect, Stream } from "effect";
import type { PlatformError } from "effect/PlatformError";
import { ChildProcess, ChildProcessSpawner } from "effect/process";

export class JjError extends Error {
  public readonly args: string[];
  public readonly detail: string;
  public constructor(args: string[], detail: string) {
    super(`jj ${args.join(" ")}: ${detail}`);
    this.args = args;
    this.detail = detail;
  }
}

/**
 * Query-mode option for {@link jj}. Both modes inject the same transport
 * flags: `--ignore-working-copy` plus `--at-op=@`. Verified against
 * jj 0.45.1 help and fixtures:
 *
 * - `--ignore-working-copy` neither snapshots nor updates the working copy
 *   and does not import colocated Git refs, so a query observes jj's
 *   current view, possibly stale relative to the worktree and Git refs;
 *   that is the contract custody checks need.
 * - `--at-op=@` (implies `--ignore-working-copy`) additionally pins the
 *   load to the current operation head so "divergent operations will never
 *   be merged": a plain query that stumbles onto divergent operation heads
 *   would otherwise resolve them automatically, writing a
 *   "reconcile divergent operations" op into `.jj/repo/op_heads`. That was
 *   observed live: after two concurrent jj commands left divergent heads,
 *   the next `--ignore-working-copy`-only query printed "Concurrent
 *   modification detected, resolving automatically" and appended the
 *   reconcile op. Query mode must not be able to write, so it pins.
 *
 * `pinned` is the historical name custody used for exactly these flags
 * (see archive/src/custody/inventory/jj.ts); `readOnly` now means the same
 * thing and both remain accepted. Mutating subcommands stay forbidden in
 * query mode regardless of these flags. JjError still reports the logical
 * args without the injected transport flags.
 */
export type JjOptions = { readOnly?: boolean; pinned?: boolean };

/**
 * Execution concern, deliberately separate from domain inputs (query mode,
 * destinations, labels): an optional `AbortSignal` observed by the spawn.
 * When aborted mid-flight the child's process group is terminated by the
 * spawner finalizer; when already aborted the call fails fast.
 */
export type ExecutionOptions = { signal?: AbortSignal };


/** Flags shared by every query-mode invocation. */
const QUERY_FLAGS = ["--ignore-working-copy", "--at-op=@"] as const;

type JjOutcome = { stdout: string; stderr: string; exitCode: number };

/**
 * Spawn jj through the native spawner, draining both pipes concurrently
 * with waiting for exit so large template output cannot deadlock the child
 * on pipe backpressure. Output is UTF-8 text (jj human/template output);
 * trimming happens only at the text boundary in {@link jj}, not here. The
 * previous execFile 64 MiB cap is gone — streams collect whatever jj
 * emits.
 */
const jjOutcome = (
  argv: ReadonlyArray<string>,
  cwd: string | undefined,
): Effect.Effect<JjOutcome, PlatformError> =>
  Effect.gen(function* () {
    const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;
    const handle = yield* spawner.spawn(ChildProcess.make("jj", argv, { cwd, stdin: "ignore" }));
    const [stdout, stderr, exitCode] = yield* Effect.all(
      [Stream.runCollect(handle.stdout), Stream.runCollect(handle.stderr), handle.exitCode],
      { concurrency: "unbounded" },
    );
    return {
      stdout: utf8(concatBytes(stdout)),
      stderr: utf8(concatBytes(stderr)),
      exitCode,
    };
  }).pipe(Effect.scoped, Effect.provide(NodeServices.layer));

export async function jj(
  args: string[],
  cwd?: string,
  options?: JjOptions,
  execution?: ExecutionOptions,
): Promise<string> {
  const argv = [
    "--no-pager",
    "--color=never",
    ...(options?.readOnly === true || options?.pinned === true ? QUERY_FLAGS : []),
    ...args,
  ];
  try {
    const outcome = await Effect.runPromise(
      jjOutcome(argv, cwd),
      execution?.signal === undefined ? undefined : { signal: execution.signal },
    );
    if (outcome.exitCode !== 0) throw new JjError(args, outcome.stderr.trim());
    return outcome.stdout.trim();
  } catch (error) {
    if (error instanceof JjError) throw error;
    // An aborted signal means the spawn was interrupted, not that jj failed;
    // report that instead of a squashed interruption cause.
    if (execution?.signal?.aborted === true) throw new JjError(args, "interrupted");
    throw error instanceof Error
      ? new JjError(args, error.message)
      : new JjError(args, String(error));
  }
}

export function lines(output: string): string[] {
  return output === "" ? [] : output.split("\n").filter(Boolean);
}

export async function exists(path: string): Promise<boolean> {
  return (await stat(path, { throwIfNoEntry: false })) !== undefined;
}

export async function isDirectory(path: string): Promise<boolean> {
  const info = await stat(path, { throwIfNoEntry: false });
  return info !== undefined && info.isDirectory();
}

export const REF_TEMPLATE: string =
  'name ++ "\\t" ++ if(remote,remote,"-") ++ "\\t" ++ ' +
  'if(normal_target,normal_target.commit_id(),"conflict") ++ "\\t" ++ tracked ++ "\\n"';
export const COMMIT_TEMPLATE: string =
  'commit_id ++ "\\t" ++ empty ++ "\\t" ++ ' +
  'parents.map(|c| c.commit_id()).join(",") ++ "\\t" ++ conflict ++ "\\n"';
export const HEAD_TEMPLATE = 'commit_id ++ "\\n"';

export type BookmarkRef = { name: string; remote: string; target: string; tracked: boolean };
export const refKey = (name: string, remote: string): string => `${name}\t${remote}`;

export async function refs(
  dest: string,
  options?: JjOptions,
  execution?: ExecutionOptions,
): Promise<Map<string, BookmarkRef>> {
  const result = new Map<string, BookmarkRef>();
  for (const line of lines(
    await jj(["bookmark", "list", "--all-remotes", "-T", REF_TEMPLATE], dest, options, execution),
  )) {
    const parts = line.split("\t");
    if (parts.length !== 4) throw new Error(`malformed bookmark line: ${line}`);
    result.set(refKey(parts[0], parts[1]), {
      name: parts[0],
      remote: parts[1],
      target: parts[2],
      tracked: parts[3] === "true",
    });
  }
  return result;
}

export type Revision = { commit: string; empty: boolean; parents: string[]; conflict: boolean };

export async function revision(
  dest: string,
  rev: string,
  execution?: ExecutionOptions,
): Promise<Revision> {
  const output = await jj(["log", "-G", "-r", rev, "-T", COMMIT_TEMPLATE], dest, undefined, execution);
  const parts = output.split("\t");
  if (parts.length !== 4) throw new Error(`malformed revision line for ${rev}: ${output}`);
  return {
    commit: parts[0],
    empty: parts[1] === "true",
    parents: parts[2] === "" ? [] : parts[2].split(","),
    conflict: parts[3] === "true",
  };
}

export async function ancestor(
  dest: string,
  older: string,
  newer: string,
  execution?: ExecutionOptions,
): Promise<boolean> {
  return Number(
    await jj(["log", "-r", `${older}::${newer}`, "--count"], dest, undefined, execution),
  ) > 0;
}

/** Decode jj text output as UTF-8, replacing invalid bytes like execFile did. */
const utf8 = (bytes: Uint8Array): string => new TextDecoder("utf-8").decode(bytes);

const concatBytes = (chunks: Iterable<Uint8Array>): Uint8Array => {
  let size = 0;
  for (const chunk of chunks) size += chunk.byteLength;
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
};
