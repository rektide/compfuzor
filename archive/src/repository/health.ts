import { jj, JjError, refs } from "./jj.ts";

/**
 * Health preflight mode. The default is the historical behavior: ordinary
 * jj commands, which may snapshot the working copy and import colocated
 * Git refs (see the restructure checkpoint note). `readOnly: true` runs
 * both probes with `--ignore-working-copy` so the checkout's jj state is
 * observed, never mutated — the mode custody contracts must use.
 */
export type PreflightOptions = { readOnly?: boolean };

/** Materialize all visible view heads, including bare heads and bookmark conflict terms. */
export async function preflight(dest: string, options: PreflightOptions = {}): Promise<string[]> {
  try {
    await jj(["log", "-G", "-r", "visible_heads()", "-T", 'commit_id ++ "\\n"'], dest, options);
  } catch (error) {
    if (!(error instanceof JjError)) throw error;
    const ghosts = [
      ...new Set(
        [...error.detail.matchAll(/Object ([0-9a-f]{40,64}) of type commit not found/gi)].map(
          (match) => match[1],
        ),
      ),
    ];
    if (ghosts.length === 0) throw error;
    throw new Error(
      `jj ghost commit(s) missing from Git object store: ${ghosts.join(", ")}. ` +
        `Resolve conflicted bookmarks and re-adopt the checkout, or explicitly run ` +
        `node '${(process.argv[1] ?? "archive/src/repo-jj-archive.ts").replaceAll("'", "'\\''")}' heal --dest '${dest.replaceAll("'", "'\\''")}' --yes (backs up .jj).`,
    );
  }
  return [...(await refs(dest, options)).values()]
    .filter((ref) => ref.target === "conflict")
    .map((ref) => `${ref.name}${ref.remote === "-" ? "" : `@${ref.remote}`}`);
}
