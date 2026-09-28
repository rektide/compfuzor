import { jj, JjError, refs } from "./jj.ts";

/** Materialize all visible view heads, including bare heads and bookmark conflict terms. */
export async function preflight(dest: string): Promise<string[]> {
  try {
    await jj(["log", "-G", "-r", "visible_heads()", "-T", 'commit_id ++ "\\n"'], dest);
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
  return [...(await refs(dest)).values()]
    .filter((ref) => ref.target === "conflict")
    .map((ref) => `${ref.name}${ref.remote === "-" ? "" : `@${ref.remote}`}`);
}
