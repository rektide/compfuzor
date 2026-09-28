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
 * global/system config so host state cannot alter what is read. Every entry
 * point drops inherited `GIT_*` environment variables — a polluted parent
 * could otherwise redirect `GIT_DIR`/`GIT_CONFIG_COUNT`/… to another
 * repository and misroute writes as well as reads — while PATH, HOME, and the
 * rest of the non-Git environment survive. Repository routing happens only
 * through `cwd` or deliberate `options.env`; private staging passes its own
 * `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/`GIT_OBJECT_DIRECTORY` there.
 */
import { NodeServices } from "@effect/platform-node";
import { Effect, Stream } from "effect";
import type { PlatformError } from "effect/PlatformError";
import { ChildProcess, ChildProcessSpawner } from "effect/process";

export type GitOptions = {
  /** Working directory for the invocation. */
  readonly cwd?: string | undefined;
  /** Environment layered over the sanitized inherited environment. */
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
 * `git` exited nonzero. The message names only the subcommand, exit status,
 * and working directory; the `argv` and stderr bytes are retained as fields
 * for deliberate access, so source contents passed as arguments or echoed by
 * Git cannot leak into logs by accident.
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
    // Only a leading non-flag argument can be the subcommand; anything later
    // may be caller data (paths, values) and stays out of the message.
    const sub =
      init.argv[0] === undefined || init.argv[0].startsWith("-") ? "" : ` ${init.argv[0]}`;
    const where = init.cwd === undefined ? "" : ` (cwd ${init.cwd})`;
    super(
      `git${sub} exited ${init.exitCode}${where}; argv and stderr are retained ` +
        `on the error, not printed`,
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

/**
 * Inherited environment minus every `GIT_*` variable: a polluted parent
 * process (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`,
 * `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_COMMON_DIR`, `GIT_NAMESPACE`,
 * `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n`,
 * `GIT_CONFIG_PARAMETERS`, …) must not be able to redirect a command that
 * names its repository by `cwd` to some other repository — that matters for
 * writes (update-ref, hash-object -w) as much as for reads. PATH, HOME, and
 * the rest of the non-Git environment survive. Git's network-facing variables
 * (`GIT_SSH_COMMAND`, `GIT_ASKPASS`, …) are stripped with the prefix; no
 * current helper does network operations, and one that does must pass its
 * agent/auth configuration deliberately through `options.env`.
 */
const sanitizedEnv = (): Record<string, string | undefined> => {
  const clean: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (!key.startsWith("GIT_")) clean[key] = value;
  }
  return clean;
};

/** Shared runner: sanitized inheritance, deliberate routing, native spawn. */
const spawnGit = (
  args: ReadonlyArray<string>,
  options: GitOptions,
): Effect.Effect<GitResult, PlatformError> =>
  Effect.gen(function* () {
    const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;
    const handle = yield* spawner.spawn(
      ChildProcess.make("git", args, {
        cwd: options.cwd,
        // Only deliberate caller env can route: sanitized inheritance,
        // then `options.env` (private stage sets GIT_DIR/GIT_WORK_TREE/…).
        env: { ...sanitizedEnv(), ...options.env },
        extendEnv: false,
        stdin: options.input === undefined ? "ignore" : Stream.make(options.input),
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

/** Run `git args`, collecting raw stdout/stderr bytes and the exit code. */
export const git = (
  args: ReadonlyArray<string>,
  options?: GitOptions,
): Effect.Effect<GitResult, PlatformError> => spawnGit(args, options ?? {});

/**
 * Read-only `git`: disables auto gc/maintenance on the argv and forces
 * `readEnv` after any caller env — the isolation keys cannot be switched off
 * through `options.env` — for inventory-style queries that must not mutate
 * the source or follow host-level config and replacement state.
 */
export const gitRead = (
  args: ReadonlyArray<string>,
  options?: GitOptions,
): Effect.Effect<GitResult, PlatformError> =>
  spawnGit(["-c", "gc.auto=0", "-c", "maintenance.auto=false", ...args], {
    ...options,
    env: { ...options?.env, ...readEnv },
  });

/**
 * Checked `git`: fails with `GitError` on nonzero exit, otherwise returns
 * stdout bytes. Stderr stays on the error, separate from its message. The
 * ref-store uses this for destination writes: sanitized inheritance plus its
 * deliberate env decides where the write lands.
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
