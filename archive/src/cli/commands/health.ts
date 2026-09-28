/**
 * `health` — ghost-head preflight and conflicted-bookmark report. Runs in the
 * read-only query mode (`--ignore-working-copy`): the checkout's jj state is
 * observed, never snapshotted or re-imported.
 */
import { Console, Effect } from "effect";
import { Command } from "effect/cli";
import { runLibrary } from "../failure.ts";
import { destFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";
import { preflight } from "../../repository/health.ts";

export const health: AnyCommand = Command.make("health", { dest: destFlag }, (input) =>
  runLibrary((signal) => preflight(input.dest, { readOnly: true }, { signal })).pipe(
    Effect.flatMap((conflicts) =>
      Console.log(
        conflicts.length
          ? `Visible heads OK; conflicted bookmarks: ${conflicts.join(", ")}`
          : "Visible heads OK; no conflicted bookmarks",
      ),
    ),
  ),
).pipe(
  Command.withDescription(
    "Materialize visible_heads() and list conflicted bookmarks; no mutations.",
  ),
);
