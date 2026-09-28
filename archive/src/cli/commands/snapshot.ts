/** `snapshot` — snapshot worktree state and import colocated Git refs. */
import { Console, Effect } from "effect";
import { Command } from "effect/cli";
import { runLibrary } from "../failure.ts";
import { destFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";
import { snapshot } from "../../repository/snapshot.ts";

export const snapshotCommand: AnyCommand = Command.make("snapshot", { dest: destFlag }, (input) =>
  runLibrary(() => snapshot(input.dest)).pipe(
    Effect.flatMap((result) => Console.log(`Snapshotted ${result.dest}`)),
  ),
).pipe(
  Command.withDescription("Snapshot current tracked/untracked work and import colocated Git refs."),
);
