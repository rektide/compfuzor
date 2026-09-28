/**
 * The command registry — the toolkit's composition seam. Adding a command is
 * a new named module under commands/ plus one entry here; grouping (e.g. a
 * future custody group) can switch entries to `[group, [commands]]` form
 * without touching root.ts or main.ts. Custody commands (`adopt`,
 * `verify-adoption`) are deliberately absent until their implementations
 * exist — no stub successes. `complete` is wired in root.ts because it needs
 * the root command itself.
 */
import { fetchCommand } from "./commands/fetch.ts";
import { harvestCommand } from "./commands/harvest.ts";
import { health } from "./commands/health.ts";
import { healCommand } from "./commands/heal.ts";
import { refresh } from "./commands/refresh.ts";
import { remotesCommand } from "./commands/remotes.ts";
import { self } from "./commands/self.ts";
import { snapshotCommand } from "./commands/snapshot.ts";
import type { AnyCommand } from "./types.ts";

export const commands: ReadonlyArray<AnyCommand> = [
  refresh,
  health,
  snapshotCommand,
  harvestCommand,
  remotesCommand,
  fetchCommand,
  healCommand,
  self,
];
