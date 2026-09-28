/**
 * `fetch` — safe single-remote fetch: snapshot, harvest dirty `@` if needed,
 * freeze tracked local bookmarks, fetch without abandoning unreachable
 * commits. Reconciliation stays with `refresh`.
 */
import { Console, Effect } from "effect";
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
  },
  (input) =>
    runLibrary(() =>
      fetchRemote({ dest: input.dest, label: input.label, remote: input.remote }),
    ).pipe(
      Effect.flatMap((result) => {
        const lines = result.notices.map(
          (notice) => `BOOKMARK CREATED  ${notice.name} -> ${notice.target}`,
        );
        lines.push(`Fetched ${result.remote}; local bookmarks remain frozen until refresh`);
        return Console.log(lines.join("\n"));
      }),
    ),
).pipe(
  Command.withDescription("Snapshot, harvest dirty @, freeze tracked refs, then fetch one remote."),
);
