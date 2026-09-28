/**
 * `remotes` — declared-vs-actual remote URL policy. Differences fail loudly
 * with the reconcile command; only `--reconcile` applies them.
 */
import { Console, Effect } from "effect";
import { Command, Flag } from "effect/cli";
import { runLibrary } from "../failure.ts";
import { destFlag, remotesFlag, repoFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";
import { declaredRemotes, mismatchError, reconcile, remoteDiff } from "../../repository/remotes.ts";

export const remotesCommand: AnyCommand = Command.make(
  "remotes",
  {
    dest: destFlag,
    repo: repoFlag,
    remotes: remotesFlag,
    reconcile: Flag.Boolean("reconcile").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Apply missing or mismatched remote URLs"),
    ),
  },
  (input) =>
    runLibrary(async (signal) => {
      const diff = await remoteDiff(input.dest, declaredRemotes(input.repo, input.remotes), {
        signal,
      });
      if (input.reconcile) {
        await reconcile(input.dest, diff, { signal });
        return diff.length
          ? `Reconciled ${diff.map(({ name }) => name).join(", ")}`
          : "Remotes match";
      }
      if (diff.length) throw mismatchError(input.dest, diff, input.repo, input.remotes);
      return "Remotes match";
    }).pipe(Effect.flatMap((message) => Console.log(message))),
).pipe(
  Command.withDescription(
    "Compare declared remote URLs; --reconcile deliberately applies differences.",
  ),
);
