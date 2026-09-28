/** `heal` — last-resort jj re-adoption from Git refs, gated on `--yes`. */
import { Console, Effect } from "effect";
import { Command, Flag } from "effect/cli";
import { runLibrary } from "../failure.ts";
import { destFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";
import { heal } from "../../recovery/heal.ts";

export const healCommand: AnyCommand = Command.make(
  "heal",
  {
    dest: destFlag,
    yes: Flag.Boolean("yes").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Required explicit permission to back up and replace .jj"),
    ),
  },
  (input) =>
    runLibrary((signal) => heal(input.dest, input.yes, { signal })).pipe(
      Effect.flatMap((backup) =>
        Console.log(`Re-adopted ${input.dest}; old jj state preserved at ${backup}`),
      ),
    ),
).pipe(
  Command.withDescription(
    "Back up .jj and re-adopt from Git refs; loses jj-only operation history.",
  ),
);
