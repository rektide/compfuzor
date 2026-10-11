/** Read only native fuze membership; advertisements never establish membership. */
import { lstat, readFile, readdir, realpath } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  fail,
  name,
  parseFuze,
  parseFuzing,
  type Contribution,
  type Deployment,
  type Fuze,
} from "./model.ts";

export type Invocation = {
  member: string;
  source: string;
  deployment: Deployment;
  contribution: Contribution;
  // Resolved resource, not a shell command string.
  resource: string;
};
export type Plan = {
  version: 1;
  mode: "inspection";
  fuze: Fuze;
  action: string;
  members: Array<{
    id: string;
    reference: string;
    state: "disabled" | "selected" | "not-selected";
  }>;
  invocations: Invocation[];
};

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

export async function planFuze(deploymentDir: string, action: string): Promise<Plan> {
  const root = await realpath(deploymentDir);
  const fuze = parseFuze(JSON.parse(await readFile(join(root, "etc/fuze.json"), "utf8")));
  if ((await realpath(fuze.deployment.dir)) !== root)
    fail("fuze deployment does not match selected root");
  name(action, "selected action");
  if (!Object.hasOwn(fuze.actions, action)) fail(`unknown action: ${action}`);
  const members: Plan["members"] = [];
  const invocations: Invocation[] = [];
  const seen = new Set<string>();
  const membership = join(root, "etc/fuze.d");
  for (const filename of (await readdir(membership)).sort(compare)) {
    const match = /^(.*)\.json(\.disabled)?$/.exec(filename);
    if (!match) continue;
    const id = name(match[1], "membership ID");
    if (seen.has(id)) fail(`conflicting membership slots: ${id}`);
    seen.add(id);
    const reference = join(membership, filename);
    if (!(await lstat(reference)).isSymbolicLink())
      fail(`membership must be a symlink: ${reference}`);
    if (match[2]) {
      members.push({ id, reference, state: "disabled" });
      continue;
    }
    const source = await realpath(reference);
    const member = parseFuzing(JSON.parse(await readFile(source, "utf8")));
    if (member.id !== id) fail(`membership ID mismatch: ${id} references ${member.id}`);
    if (
      member.target.fuze !== fuze.id ||
      member.target.scope !== fuze.scope ||
      (await realpath(member.target.dir)) !== root
    )
      fail(`target mismatch for ${id}`);
    // Descriptor home must agree with its claimed constituent, including normal
    // Compfuzor etc -> ETCS_DIR exposure links. No inference from nearby files.
    if ((await realpath(join(member.deployment.dir, "etc/fuzings", `${id}.json`))) !== source)
      fail(`descriptor is not at its declared constituent home: ${id}`);
    for (const [key, contribution] of Object.entries(member.actions)) {
      if (!Object.hasOwn(fuze.actions, key)) fail(`unknown action ${key} from ${id}`);
      if (fuze.actions[key].kind !== contribution.kind)
        fail(`action kind mismatch for ${id}/${key}`);
    }
    const contribution = member.actions[action];
    members.push({ id, reference, state: contribution ? "selected" : "not-selected" });
    if (contribution)
      invocations.push({
        member: id,
        source,
        deployment: member.deployment,
        contribution,
        resource:
          contribution.kind === "zim-import"
            ? member.deployment.dir
            : resolve(member.deployment.dir, contribution.path),
      });
  }
  for (const id of fuze.actions[action].required)
    if (!invocations.some((entry) => entry.member === id))
      fail(`required member is unavailable for ${action}: ${id}`);
  invocations.sort(
    (a, b) => a.contribution.order - b.contribution.order || compare(a.member, b.member),
  );
  return { version: 1, mode: "inspection", fuze, action, members, invocations };
}
