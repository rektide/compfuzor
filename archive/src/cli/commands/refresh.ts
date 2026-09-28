/**
 * `refresh` — the composed archive convergence operation for Ansible and
 * humans. Argument-value validation (update choice, depth, remotes JSON,
 * submodule refusal) intentionally stays in the library so the exact
 * diagnostics operators match on keep flowing through the failure boundary.
 */
import { Console, Effect, Option } from "effect";
import { Command, Flag } from "effect/cli";
import { runLibrary } from "../failure.ts";
import { destFlag, labelFlag, remotesFlag, repoFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";
import { refreshArchive } from "../../repository/refresh.ts";
import type { RefreshResult } from "../../repository/refresh.ts";

export const refresh: AnyCommand = Command.make(
  "refresh",
  {
    dest: destFlag,
    repo: repoFlag,
    remotes: remotesFlag,
    label: labelFlag,
    remote: Flag.String("remote").pipe(
      Flag.withDefault("origin"),
      Flag.withDescription("Selected declared remote"),
    ),
    branch: Flag.String("branch").pipe(
      Flag.withDefault("HEAD"),
      Flag.withDescription("Branch or branch@remote; HEAD chooses main then master"),
    ),
    update: Flag.String("update").pipe(
      Flag.withDefault("true"),
      Flag.withDescription("Fetch/reconcile: true or false"),
    ),
    depth: Flag.optional(
      Flag.String("depth").pipe(Flag.withDescription("Clone depth (only for new archives)")),
    ),
    submodules: Flag.Boolean("submodules").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Unsupported: fail rather than silently recurse"),
    ),
    json: Flag.Boolean("json").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Exactly one JSON line on stdout for Ansible"),
    ),
    "reconcile-remotes": Flag.Boolean("reconcile-remotes").pipe(
      Flag.withDefault(false),
      Flag.withDescription("Explicitly add/rewrite declared remotes before refresh"),
    ),
  },
  (input) =>
    runLibrary((signal) =>
      refreshArchive(
        {
          dest: input.dest,
          repo: input.repo,
          remotes: input.remotes,
          label: input.label,
          remote: input.remote,
          version: input.branch,
          update: input.update,
          depth: Option.getOrElse(input.depth, () => undefined),
          submodules: input.submodules,
          reconcileRemotes: input["reconcile-remotes"],
        },
        { signal },
      ),
    ).pipe(Effect.flatMap((result) => render(result, input.json))),
).pipe(
  Command.withDescription(
    "Snapshot, preserve recovery tips, fetch, and reconcile the selected base and worktree.",
  ),
);

const render = (result: RefreshResult, json: boolean) => {
  if (json) return Console.log(JSON.stringify(result));
  const lines = [result.changed ? "Archive changed" : "Archive unchanged"];
  for (const notice of result.notices) {
    lines.push(
      notice.kind === "bookmark-created"
        ? `BOOKMARK CREATED  ${notice.name} -> ${notice.target}`
        : `REPO NOTICE ${notice.message}`,
    );
  }
  return Console.log(lines.join("\n"));
};
