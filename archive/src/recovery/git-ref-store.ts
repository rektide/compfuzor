/** Destination-only adapter: reads every Git ref, then performs one immutable transaction. */
import { Effect } from "effect";
import { oid, refName } from "../custody/codec.ts";
import { CustodyError, invalid } from "../custody/errors.ts";
import { gitChecked, gitRead, readEnv, utf8Fatal } from "../repository/git.ts";
import { createTransactionStdin, type RefStore, type RefTarget } from "./transaction.ts";

export class GitRefStore implements RefStore {
  public readonly destination: string;
  public readonly signal: AbortSignal | undefined;
  /**
   * Bind the calling Effect's cancellation signal to every Git child spawned
   * by this Promise adapter. An aborted update-ref transaction has uncertain
   * outcome: callers reinspect refs on retry, never roll it back or guess.
   */
  public constructor(destination: string, execution: { readonly signal?: AbortSignal } = {}) {
    this.destination = destination;
    this.signal = execution.signal;
  }

  public async list(): Promise<ReadonlyMap<string, string>> {
    try {
      this.signal?.throwIfAborted();
      const formatResult = await Effect.runPromise(
        gitRead(["rev-parse", "--show-object-format"], {
          cwd: this.destination,
        }),
        { signal: this.signal },
      );
      this.signal?.throwIfAborted();
      if (formatResult.exitCode !== 0)
        throw new Error(`Git object-format inspection failed (${formatResult.exitCode})`);
      const format = utf8Fatal(formatResult.stdout).trim();
      if (format !== "sha1" && format !== "sha256")
        invalid("unsupported destination object format");
      const refs = await Effect.runPromise(
        gitRead(["for-each-ref", "--format=%(refname)%00%(objectname)"], {
          cwd: this.destination,
        }),
        { signal: this.signal },
      );
      this.signal?.throwIfAborted();
      if (refs.exitCode !== 0) throw new Error(`Git ref listing failed (${refs.exitCode})`);
      const output = utf8Fatal(refs.stdout);
      const observed = new Map<string, string>();
      for (const line of output === "" ? [] : output.split("\n").slice(0, -1)) {
        const fields = line.split("\0");
        if (fields.length !== 2) invalid("malformed Git ref listing");
        const name = refName(fields[0]);
        if (observed.has(name)) invalid("duplicate Git ref in listing");
        observed.set(name, oid(fields[1], format));
      }
      if (output !== "" && !output.endsWith("\n")) invalid("truncated Git ref listing");
      return observed;
    } catch (error) {
      this.signal?.throwIfAborted();
      throw new CustodyError(
        "inspection-failed",
        `destination Git ref inspection failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  public async createAtomically(
    missing: readonly RefTarget[],
    matching: readonly RefTarget[],
  ): Promise<void> {
    this.signal?.throwIfAborted();
    const input = new TextEncoder().encode(createTransactionStdin(missing, matching));
    // Git's prepare checks every verify/create and its commit updates all or
    // none. No batch-updates, no dereferencing symbolic refs, no force writes.
    await Effect.runPromise(
      gitChecked(
        ["-c", "gc.auto=0", "-c", "maintenance.auto=false", "update-ref", "--stdin", "--no-deref"],
        {
          cwd: this.destination,
          env: readEnv,
          input,
        },
      ),
      { signal: this.signal },
    );
    this.signal?.throwIfAborted();
  }
}
