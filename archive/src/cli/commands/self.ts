/** `self` — detect the standard ~/archive/rektide/compfuzor checkout. */
import { Console, Effect, Option } from "effect";
import { Command, Flag } from "effect/cli";
import { runLibrary } from "../failure.ts";
import type { AnyCommand } from "../types.ts";
import { locateCompfuzor } from "../../repository/self.ts";

export const self: AnyCommand = Command.make(
  "self",
  {
    "archive-dir": Flag.optional(
      Flag.String("archive-dir").pipe(
        Flag.withDescription("Override ~/archive for detection (useful for fixtures)"),
      ),
    ),
    freshen: Flag.Boolean("freshen").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Opt in to fetching origin of detected checkout"),
    ),
  },
  (input) =>
    runLibrary((signal) =>
      locateCompfuzor(
        input.freshen,
        Option.getOrElse(input["archive-dir"], () => undefined),
        { signal },
      ),
    ).pipe(
      Effect.flatMap((location) =>
        Console.log(
          location === null
            ? "No compfuzor archive checkout detected"
            : `${location}${input.freshen ? " (origin fetched)" : ""}`,
        ),
      ),
    ),
).pipe(Command.withDescription("Detect ~/archive/rektide/compfuzor; optionally fetch its origin."));
