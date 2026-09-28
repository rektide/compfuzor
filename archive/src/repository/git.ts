/**
 * Concrete Git adapter over Effect's native child-process support.
 *
 * `git` spawns the installed `git` executable through `ChildProcessSpawner`
 * (provided by `NodeServices.layer`) and returns raw stdout/stderr bytes plus
 * the exit code: nothing here decodes, prints, or retries. Scope, stream
 * draining, and cancellation belong to the spawner; we only collect bytes and
 * validate the exit code at the callsite that cares. There is deliberately no
 * process framework, capability abstraction, or write allowlist — every
 * mutation is an auditable concrete argv at its caller.
 *
 * `gitRead` is the read-only shape used for source inventory: it opts out of
 * replace refs, lazy fetches, optional locks, auto maintenance, and inherited
 * global/system config so host state cannot alter what is read. Private
 * staging commands pass their own `GIT_DIR`/`WORK_TREE`/`INDEX`/
 * `OBJECT_DIRECTORY` through `env` on the base `git`.
 */
import { NodeServices } from "@effect/platform-node";
import { Effect, Stream } from "effect";
import type { PlatformError } from "effect/PlatformError";
import { ChildProcess, ChildProcessSpawner } from "effect/process";

export type GitOptions = {
  /** Working directory for the invocation. */
  readonly cwd?: string | undefined;
  /** Environment layered over the inherited process environment. */
  readonly env?: Record<string, string | undefined> | undefined;
  /** Bytes piped to stdin; stdin is `/dev/null` when absent. */
  readonly input?: Uint8Array | undefined;
};

export type GitResult = {
  readonly stdout: Uint8Array;
  readonly stderr: Uint8Array;
  readonly exitCode: number;
};

/**
 * `git` exited nonzero. The stderr bytes are retained on the error for
 * deliberate display; the message never embeds them, so source contents that
 * Git echoed cannot leak into logs by accident.
 */
export class GitError extends Error {
  public readonly argv: ReadonlyArray<string>;
  public readonly cwd: string | undefined;
  public readonly exitCode: number;
  public readonly stderr: Uint8Array;

  public constructor(init: {
    argv: ReadonlyArray<string>;
    cwd: string | undefined;
    exitCode: number;
    stderr: Uint8Array;
  }) {
    const where = init.cwd === undefined ? "" : ` (cwd ${init.cwd})`;
    super(
      `git ${init.argv.join(" ")}${where} exited ${init.exitCode}; stderr retained ` +
        `(${init.stderr.byteLength} bytes), not printed`,
    );
    this.name = "GitError";
    this.argv = init.argv;
    this.cwd = init.cwd;
    this.exitCode = init.exitCode;
    this.stderr = init.stderr;
  }
}

/** Environment that isolates a read from host and repo-convenience state. */
export const readEnv: Record<string, string> = {
  GIT_OPTIONAL_LOCKS: "0",
  GIT_NO_REPLACE_OBJECTS: "1",
  GIT_NO_LAZY_FETCH: "1",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_GLOBAL: "/dev/null",
};

/** Run `git args`, collecting raw stdout/stderr bytes and the exit code. */
export const git = (
  args: ReadonlyArray<string>,
  options?: GitOptions,
): Effect.Effect<GitResult, PlatformError> =>
  Effect.gen(function* () {
    const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;
    const handle = yield* spawner.spawn(
      ChildProcess.make("git", args, {
        cwd: options?.cwd,
        env: options?.env,
        extendEnv: true,
        stdin: options?.input === undefined ? "ignore" : Stream.make(options.input),
      }),
    );
    // Drain both pipes concurrently with waiting for exit so a large output
    // cannot deadlock the child on pipe backpressure.
    const [stdout, stderr, exitCode] = yield* Effect.all(
      [Stream.runCollect(handle.stdout), Stream.runCollect(handle.stderr), handle.exitCode],
      { concurrency: "unbounded" },
    );
    return { stdout: concatBytes(stdout), stderr: concatBytes(stderr), exitCode };
  }).pipe(Effect.scoped, Effect.provide(NodeServices.layer));

/**
 * Read-only `git`: disables auto gc/maintenance on the argv and layers
 * `readEnv` (caller `env` still wins) for inventory-style queries that must
 * not mutate the source or follow host-level config and replacement state.
 */
export const gitRead = (
  args: ReadonlyArray<string>,
  options?: GitOptions,
): Effect.Effect<GitResult, PlatformError> =>
  git(["-c", "gc.auto=0", "-c", "maintenance.auto=false", ...args], {
    ...options,
    env: { ...readEnv, ...options?.env },
  });

/**
 * Checked `git`: fails with `GitError` on nonzero exit, otherwise returns
 * stdout bytes. Stderr stays on the error, separate from its message.
 */
export const gitChecked = (
  args: ReadonlyArray<string>,
  options?: GitOptions,
): Effect.Effect<Uint8Array, GitError | PlatformError> =>
  git(args, options).pipe(
    Effect.flatMap((result) =>
      result.exitCode === 0
        ? Effect.succeed(result.stdout)
        : Effect.fail(
            new GitError({
              argv: args,
              cwd: options?.cwd,
              exitCode: result.exitCode,
              stderr: result.stderr,
            }),
          ),
    ),
  );

/**
 * Decode Git output as UTF-8, throwing on invalid bytes instead of replacing
 * them. For parsing `--z` inventory records where mangled bytes would silently
 * corrupt paths and object identities.
 */
export const utf8Fatal = (bytes: Uint8Array): string =>
  new TextDecoder("utf-8", { fatal: true }).decode(bytes);

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
