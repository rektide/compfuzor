/**
 * `complete` — generate a tab-completion script for a shell. bash/zsh/fish
 * come from Effect CLI's native generator (invoked through the built-in
 * `--completions` action against the real command tree, so scripts cannot
 * drift from actual flags); PowerShell uses the static generator in
 * ../completions.ts because upstream has none.
 */
import { Console } from "effect";
import { Argument, Command } from "effect/cli";
import { powershellCompletion } from "../completions.ts";
import type { AnyCommand } from "../types.ts";
import { VERSION } from "../version.ts";

const subcommandNames = (root: AnyCommand): ReadonlyArray<string> =>
  root.subcommands.flatMap((group) => group.commands.map((command) => command.name));

/**
 * Takes the root command lazily: `complete` is part of that same tree, so the
 * reference must stay a thunk to avoid an import cycle.
 */
export const completeCommand = (root: () => AnyCommand): AnyCommand =>
  Command.make(
    "complete",
    {
      shell: Argument.Literals("shell", ["bash", "zsh", "fish", "powershell"]).pipe(
        Argument.withDescription("Shell to generate a completion script for"),
      ),
    },
    (input) =>
      input.shell === "powershell"
        ? Console.log(powershellCompletion("repo-jj-archive", subcommandNames(root())))
        : // Rendered through the built-in action (with the ambient services,
          // so the buffered console and formatter apply) — the command tree
          // stays the single source of completion truth.
          Command.runWith(root(), { version: VERSION, renderErrors: false })([
            "--completions",
            input.shell,
          ]),
  ).pipe(Command.withDescription("Generate a tab-completion script for the given shell."));
