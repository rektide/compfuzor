/**
 * Erased command types for the registry and cross-module seams.
 *
 * `Command.Any` is not reachable through the `effect/cli` barrel alias, and
 * isolatedDeclarations requires exported command constants to carry explicit
 * annotations; these aliases provide both. Precise input typing stays inside
 * each command module, where `Command.make` infers it from the config.
 */
import type { Command } from "effect/cli";

/** A toolkit command with its input type erased; for registries and thunks. */
export type AnyCommand = Command.Command<any, any, any, any, any>;

/** The root command: every handler's environment requirement is the CLI Environment. */
export type RootCommand = Command.Command<"repo-jj-archive", any, any, any, Command.Environment>;
