/**
 * `fetch` — safe single-remote fetch: snapshot, harvest dirty `@` if needed,
 * fetch without abandoning unreachable commits. Tracking changes are opt-in;
 * reconciliation stays with `refresh`.
 */
import { Console, Effect, Option } from "effect";
import { Command, Flag } from "effect/cli";
import { runLibrary } from "../failure.ts";
import { destFlag, labelFlag } from "../flags.ts";
import type { AnyCommand } from "../types.ts";
import { fetchRemote } from "../../repository/fetch.ts";

export const fetchCommand: AnyCommand = Command.make(
  "fetch",
  {
    dest: destFlag,
    remote: Flag.String("remote").pipe(
      Flag.withDefault("origin"),
      Flag.withDescription("Existing remote to fetch"),
    ),
    label: labelFlag,
    branch: Flag.optional(
      Flag.String("branch").pipe(
        Flag.withDescription("Fetch only this branch; required for untrack=selected"),
      ),
    ),
    untrack: Flag.String("untrack").pipe(
      Flag.withDefault("none"),
      Flag.withDescription("Explicit tracking override: none|selected|all"),
    ),
  },
  (input) =>
    runLibrary((signal) =>
      fetchRemote(
        {
          dest: input.dest,
          label: input.label,
          remote: input.remote,
          branch: Option.getOrElse(input.branch, () => undefined),
          untrack: input.untrack as "none" | "selected" | "all",
        },
        { signal },
      ),
    ).pipe(
      Effect.flatMap((result) => {
        const lines = result.notices.map(
          (notice) => `BOOKMARK CREATED  ${notice.name} -> ${notice.target}`,
        );
        lines.push(`Fetched ${result.remote}; run refresh to reconcile the selected checkout`);
        return Console.log(lines.join("\n"));
      }),
    ),
).pipe(
  Command.withDescription("Snapshot and fetch a remote; optionally untrack selected bookmarks."),
);
