/**
 * Shared flag definitions reused across command modules. Definitions live
 * outside the commands so help text and parsing stay identical wherever a
 * concept (destination checkout, declared origin, …) appears.
 */
import { Flag } from "effect/cli";

export const destFlag: Flag.Flag<string> = Flag.String("dest").pipe(
  Flag.withDescription("Path to jj-colocated archive checkout"),
);

export const repoFlag: Flag.Flag<string> = Flag.String("repo").pipe(
  Flag.withDescription("Declared origin URL"),
);

export const remotesFlag: Flag.Flag<string> = Flag.String("remotes").pipe(
  Flag.withDefault("{}"),
  Flag.withDescription("JSON object of additional remote names and URLs"),
);

export const labelFlag: Flag.Flag<string> = Flag.String("label").pipe(
  Flag.withDescription("Deployment label for recovery bookmarks"),
);
