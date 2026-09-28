import { jj, lines, type ExecutionOptions } from "./jj.ts";

export type RemoteDifference = { name: string; declared: string; actual: string | null };
const REMOTE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const quote = (value: string): string => `'${value.replaceAll("'", "'\\''")}'`;

export function declaredRemotes(repo: string, remotes: string): Map<string, string> {
  const json: unknown = JSON.parse(remotes);
  if (json === null || typeof json !== "object" || Array.isArray(json))
    throw new Error("--remotes must be a JSON object mapping remote names to URLs");
  const declared = new Map<string, unknown>([["origin", repo], ...Object.entries(json)]);
  const urls = new Map<string, string>();
  for (const [name, url] of declared) {
    if (!REMOTE_NAME.test(name) || typeof url !== "string" || !url)
      throw new Error("remote names or URLs are invalid");
    urls.set(name, url);
  }
  return urls;
}

export async function remoteDiff(
  dest: string,
  urls: Map<string, string>,
  execution?: ExecutionOptions,
): Promise<RemoteDifference[]> {
  const actual = new Map<string, string>();
  for (const line of lines(await jj(["git", "remote", "list"], dest, undefined, execution))) {
    const space = line.indexOf(" ");
    actual.set(
      space === -1 ? line : line.slice(0, space),
      space === -1 ? "" : line.slice(space + 1),
    );
  }
  return [...urls]
    .filter(([name, url]) => actual.get(name) !== url)
    .map(([name, declared]) => ({ name, declared, actual: actual.get(name) ?? null }));
}

export function mismatchError(
  dest: string,
  differences: RemoteDifference[],
  repo: string,
  remotes: string,
): Error {
  const table = differences
    .map(
      ({ name, declared, actual }) =>
        `${name}\t${JSON.stringify(declared)}\t${JSON.stringify(actual ?? "(missing)")}`,
    )
    .join("\n");
  return new Error(
    `declared remote URL mismatch (no remote was changed):\n` +
      `name\tdeclared\tactual\n${table}\n` +
      `To apply deliberately: node ${quote(process.argv[1] ?? "archive/src/repo-jj-archive.ts")} remotes --dest ${quote(dest)} ` +
      `--repo ${quote(repo)} --remotes ${quote(remotes)} --reconcile`,
  );
}

/** Adds missing remotes and rewrites mismatches only on explicit operator request. */
export async function reconcile(
  dest: string,
  differences: RemoteDifference[],
  execution?: ExecutionOptions,
): Promise<void> {
  for (const { name, declared, actual } of differences) {
    await jj(
      ["git", "remote", actual === null ? "add" : "set-url", name, declared],
      dest,
      undefined,
      execution,
    );
  }
}
