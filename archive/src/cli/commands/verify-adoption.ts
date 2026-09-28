/** Source-independent receipt verification, with optional legacy drift diagnostics. */
import { mkdtemp, realpath, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { Console, Effect, Option } from "effect";
import { Command, Flag } from "effect/cli";
import { CustodyError } from "../../custody/errors.ts";
import { verifyAdoption } from "../../custody/verify.ts";
import { destFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";

const contains = (outer: string, inner: string): boolean => {
  const path = relative(outer, inner);
  return path === "" || (path !== ".." && !path.startsWith(`..${"/"}`) && !path.startsWith("/"));
};

/** Never place restoration scratch inside either checkout, including symlink aliases. */
const scratchParent = async (dest: string, legacy: string | null): Promise<string> => {
  const destReal = await realpath(dest);
  const legacyReal = legacy === null ? null : await realpath(legacy).catch(() => resolve(legacy));
  for (const candidate of [tmpdir(), dirname(destReal)]) {
    const parent = await realpath(candidate);
    if (!contains(destReal, parent) && (legacyReal === null || !contains(legacyReal, parent)))
      return parent;
  }
  throw new CustodyError(
    "invalid-input",
    "no private scratch parent outside the destination and legacy roots",
  );
};

export const verifyAdoptionCommand: AnyCommand = Command.make(
  "verify-adoption",
  {
    dest: destFlag,
    receipt: Flag.String("receipt").pipe(
      Flag.withDescription("Full refs/adopt/receipts/<label>/<generation> ref"),
    ),
    legacy: Flag.optional(
      Flag.String("legacy").pipe(Flag.withDescription("Optional source drift diagnosis")),
    ),
    json: Flag.Boolean("json").pipe(
      Flag.withDefault(false),
      Flag.withDescription("One complete JSON result line"),
    ),
  },
  (flags) => {
    const legacy = Option.getOrNull(flags.legacy);
    return Effect.tryPromise({
      try: async (signal) => {
        const parent = await scratchParent(flags.dest, legacy);
        signal.throwIfAborted();
        const scratchRoot = await mkdtemp(join(parent, ".compfuzor-verify-"));
        // Failure retains private scratch as evidence. Success cleans only the
        // directory this command created, after verification has finalized.
        const report = await verifyAdoption(
          { dest: flags.dest, receiptRef: flags.receipt, legacy, scratchRoot },
          { signal },
        );
        signal.throwIfAborted();
        if (!report.custodyVerified || report.custodyFailures.length > 0)
          throw new CustodyError(
            "verification-failed",
            `custody verification failed: ${report.custodyFailures.map(({ code }) => code).join(", ")}`,
          );
        await rm(scratchRoot, { recursive: true });
        return report;
      },
      catch: (error) => (error instanceof Error ? error : new Error(String(error))),
    }).pipe(
      Effect.flatMap((report) =>
        Console.log(
          flags.json
            ? JSON.stringify(report)
            : [
                `Receipt: ${report.receiptRef} (${report.receiptCommitOid})`,
                `Custody verified: ${report.custodyVerified}`,
                `Source drift: ${report.sourceDrift}; destination drift: ${report.destinationDrift}`,
                ...report.retirementUnresolved.map(
                  ({ code, reason }) => `RETIREMENT UNRESOLVED ${code}: ${reason}`,
                ),
                "Git custody does not authorize publication or retirement.",
              ].join("\n"),
        ),
      ),
    );
  },
).pipe(
  Command.withDescription(
    "Independently check the receipt, Git pins and vault without requiring the legacy source.",
  ),
);
