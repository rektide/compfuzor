/** Create or refresh a dedicated deployment workspace without using archive @. */
import { Console, Effect, Option } from "effect";
import { Command, Flag } from "effect/cli";
import { runLibrary } from "../failure.ts";
import { labelFlag, remotesFlag, repoFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";
import { deployWorkspace } from "../../repository/deploy.ts";

export const deploy: AnyCommand = Command.make(
  "deploy",
  {
    archive: Flag.String("archive").pipe(
      Flag.withDescription("Shared jj-colocated Git archive at ~/archive/<org>/<repo>"),
    ),
    workspace: Flag.String("workspace").pipe(
      Flag.withDescription("Dedicated deployment jj workspace and Git worktree"),
    ),
    repo: repoFlag,
    remotes: remotesFlag,
    label: labelFlag,
    remote: Flag.String("remote").pipe(Flag.withDefault("origin")),
    branch: Flag.String("branch").pipe(Flag.withDefault("HEAD")),
    update: Flag.String("update").pipe(Flag.withDefault("true")),
    "fetch-scope": Flag.String("fetch-scope").pipe(
      Flag.withDefault("all"),
      Flag.withDescription("Fetch all declared branches or only the selected branch: all|selected"),
    ),
    untrack: Flag.String("untrack").pipe(
      Flag.withDefault("none"),
      Flag.withDescription("Explicit tracking override: none|selected|all"),
    ),
    "no-save-displaced": Flag.Boolean("no-save-displaced").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Leave diverged bookmarks conflicted instead of saving and resolving"),
    ),
    depth: Flag.optional(Flag.String("depth")),
    submodules: Flag.Boolean("submodules").pipe(Flag.withDefault(false)),
    json: Flag.Boolean("json").pipe(Flag.withDefault(false)),
    "reconcile-remotes": Flag.Boolean("reconcile-remotes").pipe(Flag.withDefault(false)),
  },
  (input) =>
    runLibrary((signal) =>
      deployWorkspace(
        {
          archive: input.archive,
          workspace: input.workspace,
          repo: input.repo,
          remotes: input.remotes,
          label: input.label,
          remote: input.remote,
          version: input.branch,
          update: input.update,
          fetchScope: input["fetch-scope"] as "all" | "selected",
          untrack: input.untrack as "none" | "selected" | "all",
          saveDisplaced: !input["no-save-displaced"],
          depth: Option.getOrElse(input.depth, () => undefined),
          submodules: input.submodules,
          reconcileRemotes: input["reconcile-remotes"],
        },
        { signal },
      ),
    ).pipe(
      Effect.flatMap((result) =>
        Console.log(
          input.json
            ? JSON.stringify(result)
            : result.notices
                .map(
                  (notice) =>
                    notice.message ?? `BOOKMARK CREATED  ${notice.name} -> ${notice.target}`,
                )
                .join("\n") || (result.changed ? "Workspace changed" : "Workspace unchanged"),
        ),
      ),
    ),
).pipe(Command.withDescription("Create or refresh a jj/Git deployment workspace of an archive."));
