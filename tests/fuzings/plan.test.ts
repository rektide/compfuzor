import { afterEach, describe, expect, it } from "vitest";
import {
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  readlink,
  rename,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { join } from "node:path";
import { planFuze } from "../../files/fuzings/plan.ts";
import {
  parseFuze,
  parseFuzing,
  type Contribution,
  type Fuze,
  type Fuzing,
} from "../../files/fuzings/model.ts";

const roots: string[] = [];
afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});
async function json(path: string, value: unknown): Promise<void> {
  await writeFile(path, JSON.stringify(value));
}
async function setup() {
  const root = await mkdtemp("/home/rektide/tmp-opencode/fuzings-");
  roots.push(root);
  const owner = join(root, "owner");
  const membership = join(owner, "etc/fuze.d");
  await mkdir(membership, { recursive: true });
  const fuze: Fuze = {
    version: 1,
    id: "opencode",
    deployment: { id: "opencode-git", dir: owner },
    scope: "user",
    actions: {
      refresh: { kind: "zim-import", required: [] },
      activate: { kind: "shell-source", required: [] },
      restart: { kind: "exec", required: [] },
    },
  };
  const save = () => json(join(owner, "etc/fuze.json"), fuze);
  await save();
  async function member(id: string, actions: Record<string, Contribution>, enroll = true) {
    const dir = join(root, id);
    await mkdir(join(dir, "etc/fuzings"), { recursive: true });
    const descriptor: Fuzing = {
      version: 1,
      id,
      deployment: { id, dir },
      target: { dir: owner, fuze: "opencode", scope: "user" },
      actions,
    };
    const source = join(dir, "etc/fuzings", `${id}.json`);
    const reference = join(membership, `${id}.json`);
    await json(source, descriptor);
    if (enroll) await symlink(source, reference);
    return { descriptor, source, reference, save: () => json(source, descriptor) };
  }
  return { root, owner, membership, fuze, save, member };
}

async function snapshot(root: string): Promise<unknown[]> {
  const result: unknown[] = [];
  for (const entry of (await readdir(root)).sort()) {
    const path = join(root, entry);
    const stat = await lstat(path);
    result.push([
      path,
      stat.mtimeMs,
      stat.mode,
      stat.isSymbolicLink()
        ? await readlink(path)
        : stat.isDirectory()
          ? await snapshot(path)
          : await readFile(path, "utf8"),
    ]);
  }
  return result;
}

describe("explicit fuzing action plans", () => {
  it("selects installed members only, sorts ties deterministically, and never mutates", async () => {
    const f = await setup();
    await f.member("z-proxy", {
      refresh: { kind: "zim-import", order: 60 },
      restart: { kind: "exec", order: 10, path: "bin/restart.sh", args: ["literal $(false)"] },
    });
    await f.member("a-tools", { refresh: { kind: "zim-import", order: 60 } });
    await f.member("origin", {
      refresh: { kind: "zim-import", order: 10 },
      activate: { kind: "shell-source", order: 54, path: "etc/client.zsh" },
    });
    await f.member("uninstalled", { refresh: { kind: "zim-import", order: 0 } }, false);
    const before = await snapshot(f.root);
    const plan = await planFuze(f.owner, "refresh");
    expect(plan.invocations.map((entry) => entry.member)).toEqual(["origin", "a-tools", "z-proxy"]);
    expect(plan.invocations.every((entry) => entry.contribution.kind === "zim-import")).toBe(true);
    expect(await planFuze(f.owner, "refresh")).toEqual(plan);
    expect((await planFuze(f.owner, "restart")).invocations).toMatchObject([
      {
        member: "z-proxy",
        resource: join(f.root, "z-proxy/bin/restart.sh"),
        contribution: { args: ["literal $(false)"] },
      },
    ]);
    expect((await planFuze(f.owner, "activate")).invocations).toMatchObject([
      { member: "origin", resource: join(f.root, "origin/etc/client.zsh") },
    ]);
    expect(await snapshot(f.root)).toEqual(before);
  });

  it("retains disabled dangling references but fails active missing or conflicting members", async () => {
    const f = await setup();
    const link = join(f.membership, "missing.json");
    await symlink(join(f.root, "gone.json"), `${link}.disabled`);
    expect((await planFuze(f.owner, "refresh")).members).toMatchObject([
      { id: "missing", state: "disabled" },
    ]);
    await symlink(join(f.root, "gone.json"), link);
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow();
    await rm(`${link}.disabled`);
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("ENOENT");
    await rm(link);
    const m = await f.member("proxy", { refresh: { kind: "zim-import", order: 1 } });
    await symlink(m.source, `${m.reference}.disabled`);
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("conflicting membership");
  });

  it("enforces required members per action, including disabled and nonparticipating", async () => {
    const f = await setup();
    f.fuze.actions.refresh.required = ["proxy"];
    await f.save();
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("required member");
    expect((await planFuze(f.owner, "restart")).invocations).toEqual([]);
    const m = await f.member("proxy", {
      restart: { kind: "exec", order: 1, path: "bin/restart.sh", args: [] },
    });
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("required member");
    m.descriptor.actions.refresh = { kind: "zim-import", order: 2 };
    await m.save();
    expect((await planFuze(f.owner, "refresh")).invocations).toHaveLength(1);
    await rename(m.reference, `${m.reference}.disabled`);
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("required member");
  });

  it("rejects wrong instance, audience, fuze, identity and action kind", async () => {
    const f = await setup();
    const m = await f.member("proxy", { refresh: { kind: "zim-import", order: 1 } });
    const original = structuredClone(m.descriptor);
    const other = join(f.root, "secondary");
    await mkdir(other);
    for (const delta of [{ dir: other }, { scope: "system" as const }, { fuze: "other" }]) {
      m.descriptor.target = { ...original.target, ...delta };
      await m.save();
      await expect(planFuze(f.owner, "refresh")).rejects.toThrow("target mismatch");
    }
    m.descriptor.target = original.target;
    m.descriptor.actions.refresh = { kind: "exec", order: 1, path: "bin/restart.sh", args: [] };
    await m.save();
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("kind mismatch");
    m.descriptor.actions = { typo: { kind: "zim-import", order: 1 } };
    await m.save();
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("unknown action typo");
    m.descriptor.id = "foreign";
    await m.save();
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("membership ID mismatch");
    await expect(planFuze(f.owner, "typo")).rejects.toThrow("unknown action: typo");
  });

  it("requires owned descriptor homes but supports Compfuzor's external etc links", async () => {
    const f = await setup();
    const m = await f.member("proxy", { refresh: { kind: "zim-import", order: 1 } });
    const movedEtc = join(f.root, "proxy-etc");
    await rename(join(m.descriptor.deployment.dir, "etc"), movedEtc);
    await symlink(movedEtc, join(m.descriptor.deployment.dir, "etc"));
    expect((await planFuze(f.owner, "refresh")).invocations[0].source).toBe(
      join(movedEtc, "fuzings/proxy.json"),
    );
    const foreign = join(f.root, "foreign.json");
    await json(foreign, m.descriptor);
    await rm(m.reference);
    await symlink(foreign, m.reference);
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("declared constituent home");
  });

  it("distinguishes empty membership from missing storage and rejects inline definitions", async () => {
    const f = await setup();
    await writeFile(join(f.membership, "README.md"), "operator notes");
    expect((await planFuze(f.owner, "refresh")).invocations).toEqual([]);
    await json(join(f.membership, "inline.json"), {});
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("must be a symlink");
    await rm(f.membership, { recursive: true });
    await expect(planFuze(f.owner, "refresh")).rejects.toThrow("ENOENT");
  });

  it("rejects malformed declarations and argument/path ambiguities", async () => {
    const f = await setup();
    const m = await f.member("proxy", { refresh: { kind: "zim-import", order: 1 } });
    for (const contribution of [
      { kind: "zim-import", order: true },
      { kind: "zim-import", order: -1 },
      { kind: "zim-import", order: 1, path: "etc/a" },
      { kind: "exec", order: 1, path: "bin/../outside", args: [] },
      { kind: "exec", order: 1, path: "bin/run", args: "--all" },
      { kind: "exec", order: 1, path: "bin/run", args: null },
      { kind: "shell-source", order: 1, path: "etc/a", args: [] },
    ])
      expect(() => parseFuzing({ ...m.descriptor, actions: { refresh: contribution } })).toThrow();
    expect(() => parseFuzing({ ...m.descriptor, enabled: false })).toThrow("unknown field");
    expect(() => parseFuzing({ ...m.descriptor, id: "proxy\n" })).toThrow("invalid descriptor ID");
    expect(() => parseFuze({ ...f.fuze, version: 2 })).toThrow("version");
    expect(() =>
      parseFuze({ ...f.fuze, actions: { refresh: { kind: "zim-import", required: null } } }),
    ).toThrow("required");
  });
});
