/**
 * Root command composition. Invoked without a subcommand it prints the
 * orientation hint (an intentional, documented success — never JSON).
 */
import { Console } from "effect";
import { Command } from "effect/cli";
import { completeCommand } from "./commands/complete.ts";
import { commands } from "./commands.ts";
import type { AnyCommand, RootCommand } from "./types.ts";

export const root: RootCommand = Command.make("repo-jj-archive", {}, () =>
  Console.log("Run repo-jj-archive --help for commands."),
).pipe(
  Command.withDescription("Composable jj archive operations; use COMMAND --help for flags."),
  Command.withSubcommands([
    ...commands,
    // `complete` reflects the whole tree, so it receives the root lazily.
    completeCommand((): AnyCommand => root),
  ]),
);
