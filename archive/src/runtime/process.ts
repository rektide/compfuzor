/**
 * Bounded, injectable subprocess execution with byte-exact Buffer I/O.
 *
 * Custody evidence plumbing needs stdout/stderr as raw bytes: Git emits
 * NUL-delimited path lists and filenames may contain newlines or invalid
 * UTF-8, and trimming or decoding through UTF-8 strings destroys that
 * evidence. Errors must also stay silent about captured output: a diagnostic
 * message that embeds stderr risks leaking repository contents. `ProcessError`
 * therefore carries the raw buffers as explicit fields for deliberate
 * inspection while its `message` withholds all process output.
 *
 * The environment and working directory are always explicit: nothing is
 * inherited implicitly from this process, so callers (Git seams in
 * `repository/git.ts`) control every injection-relevant variable.
 */
import { spawn, type ChildProcess } from "node:child_process";

export type RunRequest = Readonly<{
  /** Executable name; resolved via the request env's PATH, never a shell. */
  command: string;
  /** Argument vector passed through verbatim; no shell interpolation. */
  args: readonly string[];
  /** Working directory; required so no ambient cwd is ever used. */
  cwd: string;
  /** Complete child environment; required, never merged with our own. */
  env: Readonly<Record<string, string>>;
  stdin?: Buffer;
  /** Per-stream output bound in bytes; past it the child is killed. */
  maxBytes?: number;
  /** Wall-clock deadline after which the child is killed. */
  timeoutMs?: number;
}>;

export type RunResult = Readonly<{ stdout: Buffer; stderr: Buffer }>;

export type RunFailure =
  | Readonly<{ kind: "NonZeroExit"; exitCode: number }>
  | Readonly<{ kind: "KilledBySignal"; signal: string }>
  | Readonly<{ kind: "OutputOverflow"; stream: "stdout" | "stderr"; maxBytes: number }>
  | Readonly<{ kind: "Timeout"; timeoutMs: number }>
  | Readonly<{ kind: "SpawnError"; code?: string; message: string }>;

/** Nonzero exits (and every other failure) reject; the message never quotes output. */
export class ProcessError extends Error {
  public readonly command: string;
  public readonly args: readonly string[];
  public readonly cwd: string;
  public readonly failure: RunFailure;
  /** Raw captured bytes, truncated at the bound on overflow; never in `message`. */
  public readonly stdout: Buffer;
  public readonly stderr: Buffer;

  public constructor(props: {
    request: RunRequest;
    failure: RunFailure;
    stdout: Buffer;
    stderr: Buffer;
  }) {
    super(
      `${props.request.command} ${props.request.args.join(" ")} in ${props.request.cwd}: ` +
        `${describeFailure(props.failure)} ` +
        `(stdout ${props.stdout.length} bytes, stderr ${props.stderr.length} bytes; ` +
        `contents withheld from this message)`,
    );
    this.name = "ProcessError";
    this.command = props.request.command;
    this.args = props.request.args;
    this.cwd = props.request.cwd;
    this.failure = props.failure;
    this.stdout = props.stdout;
    this.stderr = props.stderr;
  }

  /** Deliberate stderr decoding for diagnostics; may contain repository data. */
  public stderrText(): string {
    return this.stderr.toString("utf8");
  }

  /** Deliberate stdout decoding; byte evidence should use the Buffer instead. */
  public stdoutText(): string {
    return this.stdout.toString("utf8");
  }
}

function describeFailure(failure: RunFailure): string {
  switch (failure.kind) {
    case "NonZeroExit":
      return `exited ${failure.exitCode}`;
    case "KilledBySignal":
      return `killed by signal ${failure.signal}`;
    case "OutputOverflow":
      return `exceeded the ${failure.maxBytes}-byte bound on ${failure.stream} output`;
    case "Timeout":
      return `timed out after ${failure.timeoutMs}ms`;
    case "SpawnError":
      return `could not be spawned (${failure.code ?? failure.message})`;
  }
}

export interface ProcessRunner {
  run(request: RunRequest): Promise<RunResult>;
}

export const DEFAULT_MAX_BYTES: number = 64 * 1024 * 1024;

async function nodeRun(request: RunRequest): Promise<RunResult> {
  const maxBytes = request.maxBytes ?? DEFAULT_MAX_BYTES;
  return await new Promise<RunResult>((resolve, reject) => {
    let child: ChildProcess;
    try {
      child = spawn(request.command, [...request.args], {
        cwd: request.cwd,
        env: { ...request.env },
        stdio: ["pipe", "pipe", "pipe"],
      });
    } catch (error) {
      reject(spawnFailure(request, error));
      return;
    }

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];
    let stdoutLength = 0;
    let stderrLength = 0;
    let overflow: "stdout" | "stderr" | null = null;
    let timedOut = false;
    let settled = false;

    const collect = (
      stream: "stdout" | "stderr",
      chunks: Buffer[],
      length: () => number,
    ): ((chunk: Buffer) => void) => {
      return (chunk: Buffer): void => {
        if (overflow !== null) return;
        chunks.push(chunk);
        if (length() + chunk.length > maxBytes) {
          overflow = stream;
          child.kill("SIGKILL");
        }
      };
    };
    const stdoutLengthOf = (): number => stdoutLength;
    const stderrLengthOf = (): number => stderrLength;
    child.stdout?.on(
      "data",
      collect("stdout", stdoutChunks, (): number => {
        return stdoutLengthOf();
      }),
    );
    child.stderr?.on(
      "data",
      collect("stderr", stderrChunks, (): number => {
        return stderrLengthOf();
      }),
    );

    // Hmm: the length closures above must actually track totals.
    child.stdout?.on("data", (chunk: Buffer): void => {
      stdoutLength += chunk.length;
    });
    child.stderr?.on("data", (chunk: Buffer): void => {
      stderrLength += chunk.length;
    });

    const timer =
      request.timeoutMs === undefined
        ? undefined
        : setTimeout((): void => {
            timedOut = true;
            child.kill("SIGKILL");
          }, request.timeoutMs);

    const finish = (settle: () => void): void => {
      if (settled) return;
      settled = true;
      if (timer !== undefined) clearTimeout(timer);
      settle();
    };

    child.on("error", (error: NodeJS.ErrnoException): void => {
      finish((): void => {
        reject(
          new ProcessError({
            request,
            failure: { kind: "SpawnError", code: error.code, message: error.message },
            stdout: truncate(stdoutChunks, maxBytes),
            stderr: truncate(stderrChunks, maxBytes),
          }),
        );
      });
    });

    child.on("close", (code: number | null, signal: NodeJS.Signals | null): void => {
      finish((): void => {
        const stdout = truncate(stdoutChunks, maxBytes);
        const stderr = truncate(stderrChunks, maxBytes);
        if (overflow !== null) {
          reject(
            new ProcessError({
              request,
              failure: { kind: "OutputOverflow", stream: overflow, maxBytes },
              stdout,
              stderr,
            }),
          );
          return;
        }
        if (timedOut) {
          reject(
            new ProcessError({
              request,
              failure: { kind: "Timeout", timeoutMs: request.timeoutMs ?? 0 },
              stdout,
              stderr,
            }),
          );
          return;
        }
        if (signal !== null) {
          reject(
            new ProcessError({
              request,
              failure: { kind: "KilledBySignal", signal },
              stdout,
              stderr,
            }),
          );
          return;
        }
        if (code !== 0) {
          reject(
            new ProcessError({
              request,
              failure: { kind: "NonZeroExit", exitCode: code ?? -1 },
              stdout,
              stderr,
            }),
          );
          return;
        }
        resolve({ stdout, stderr });
      });
    });

    if (request.stdin === undefined) {
      child.stdin?.end();
    } else {
      // EPIPE just means the child exited before consuming stdin; the exit
      // status or close handler reports the real failure.
      child.stdin?.on("error", (): undefined => undefined);
      child.stdin?.end(request.stdin);
    }
  });
}

function spawnFailure(request: RunRequest, error: unknown): ProcessError {
  const message = error instanceof Error ? error.message : String(error);
  const code =
    typeof (error as { code?: unknown }).code === "string"
      ? (error as { code: string }).code
      : undefined;
  return new ProcessError({
    request,
    failure: { kind: "SpawnError", code, message },
    stdout: Buffer.alloc(0),
    stderr: Buffer.alloc(0),
  });
}

function truncate(chunks: readonly Buffer[], maxBytes: number): Buffer {
  const whole = Buffer.concat(chunks.length === 0 ? [Buffer.alloc(0)] : chunks);
  return whole.length > maxBytes ? whole.subarray(0, maxBytes) : whole;
}

/** The production runner; tests inject fakes or capture requests instead. */
export const nodeRunner: ProcessRunner = { run: nodeRun };
