/**
 * Failure boundary between the Promise-based toolkit library and the Effect
 * CLI, plus the diagnostic format every consumer (launcher, Ansible, humans)
 * sees.
 *
 * Invariants: failures exit nonzero, print `repo-jj-archive: <detail>` on
 * stderr, and leave stdout empty (see output.ts for the buffering that keeps
 * help-on-parse-failure off stdout). Meaningful multi-line diagnostics such
 * as the declared/actual remotes table are intentional and preserved.
 */
import { Effect } from "effect";
import { CliError } from "effect/cli";

/**
 * A toolkit library operation rejected the request; `cause` carries the
 * original thrown error. Declared as a plain Error subclass (explicit,
 * isolatedDeclarations-friendly members) rather than a schema-derived class.
 */
export class ToolkitFailure extends Error {
  override readonly name: string = "ToolkitFailure";

  public readonly cause: unknown;

  public constructor(cause: unknown) {
    super("archive toolkit operation failed");
    this.cause = cause;
  }
}

/** Lift a (possibly throwing) Promise-returning library call into the Effect error channel. */
export const runLibrary = <A>(
  operation: (signal: AbortSignal) => Promise<A>,
): Effect.Effect<A, ToolkitFailure> =>
  Effect.tryPromise({
    try: operation,
    catch: (cause: unknown) => new ToolkitFailure(cause),
  });

const memberDetail = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

/** One diagnostic string for any failure shape the runner can produce. */
export const failureDetail = (error: unknown): string => {
  if (CliError.isCliError(error) && error._tag === "ShowHelp") {
    return error.errors.map((item) => item.message).join("; ");
  }
  if (error instanceof ToolkitFailure) return memberDetail(error.cause);
  if (error instanceof AggregateError) return error.errors.map(memberDetail).join("; ");
  return memberDetail(error);
};

/** Report a failure on stderr and mark the process exit nonzero; never touches stdout. */
export const reportFailure = (error: unknown): void => {
  console.error(`repo-jj-archive: ${failureDetail(error)}`);
  process.exitCode = 1;
};
