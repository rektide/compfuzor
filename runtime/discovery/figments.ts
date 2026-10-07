/** The only Figments integration seam. Source-mode linking is deliberate; see the checkpoint. */
import { Figment } from "figmen-ts/src/figment.ts";
import { stat } from "node:fs/promises";
import { discoverDropIns, type RootReport } from "figmen-ts/src/discovery/entries.ts";
import {
  resolveDropIns,
  type ResolvedEntry,
  type RegistryView,
} from "figmen-ts/src/discovery/resolve.ts";
import { captureDropIns } from "figmen-ts/src/discovery/capture.ts";
import { dropIns } from "figmen-ts/src/operators/drop-in.ts";
import { Json } from "figmen-ts/src/providers/data.ts";
export { xdgConfigDirs, xdgDataDirs } from "figmen-ts/src/core/xdg.ts";
export type { RootReport, ResolvedEntry, RegistryView };

/** Roots are ordered LOW to HIGH precedence, matching Figments' resolution contract. */
export async function observe(roots: readonly string[]): Promise<RegistryView> {
  return resolveDropIns(
    await discoverDropIns({
      dir: roots,
      naming: {
        extensions: [".json"],
        disabledSuffixes: [".disabled"],
      },
    }),
    { identity: "stem", symlinks: "follow", masks: true },
  );
}

/** Read exactly the observed winner, including retained disabled payloads. Never rescan. */
export async function load(entry: ResolvedEntry): Promise<unknown> {
  const source = captureDropIns([entry]);
  return Figment.new().derive(dropIns({ source })).build();
}

/** Required exact owner descriptor, without optional-file fallback or ancestor search. */
export async function loadOwner(path: string): Promise<unknown> {
  if (!(await stat(path)).isFile())
    throw new Error(`owner descriptor must refer to a regular file: ${path}`);
  return Figment.from(Json.file(path).required(true).search(false)).build();
}
