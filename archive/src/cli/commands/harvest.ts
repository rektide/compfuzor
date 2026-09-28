/** `harvest` — pin a revision under a unique harvest/<label>/ recovery bookmark. */
import { Console, Effect } from "effect";
import { Command, Flag } from "effect/cli";
import { runLibrary } from "../failure.ts";
import { destFlag, labelFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";
import { harvest } from "../../recovery/harvest.ts";
import { snapshot } from "../../repository/snapshot.ts";

export const harvestCommand: AnyCommand = Command.make(
  "harvest",
  {
    dest: destFlag,
    label: labelFlag,
    kind: Flag.String("kind").pipe(
      Flag.withDefault("manual"),
      Flag.withDescription("Recovery bookmark category"),
    ),
    target: Flag.String("target").pipe(
      Flag.withDefault("@"),
      Flag.withDescription("Revision to pin"),
    ),
    copy: Flag.Boolean("copy").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Duplicate mutable @ to a fixed change ID before pinning"),
    ),
  },
  (input) =>
    runLibrary(async (signal) => {
      // Pin only a materialized state: snapshot before creating the bookmark.
      await snapshot(input.dest, { signal });
      return harvest(input.dest, input.label, input.kind, input.target, input.copy, { signal });
    }).pipe(
      Effect.flatMap((notice) =>
        Console.log(`BOOKMARK CREATED  ${notice.name} -> ${notice.target}`),
      ),
    ),
).pipe(Command.withDescription("Pin a revision under a unique harvest/<label>/ bookmark."));
