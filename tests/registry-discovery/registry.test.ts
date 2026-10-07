import { afterEach, describe, expect, it } from "vitest";
import { readFile, readlink, rename, rm, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { fixtures } from "./fixtures.ts";
import { keybindingConsumers, keybindingProviders } from "../../runtime/keybindings/registry.ts";
import { zimProviders } from "../../runtime/zim/registry.ts";
import { inspectRegistry, lookup } from "../../runtime/registry/read.ts";
import { applyRegistration, planRegistration, register } from "../../runtime/registry/register.ts";
import { explicitPolicy, registryPolicy } from "../../runtime/registry/policy.ts";
import { load, observe } from "../../runtime/discovery/figments.ts";
import { loadManifest } from "../../files/links/manifest.ts";

const roots: string[] = [];
async function setup() {
  const fixture = await fixtures();
  roots.push(fixture.root);
  return fixture;
}
afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

async function cli(args: string[], entry = "runtime/cli/registry.ts") {
  const process = spawn(globalThis.process.execPath, [entry, ...args], {
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "",
    stderr = "";
  process.stdout.on("data", (chunk) => {
    stdout += String(chunk);
  });
  process.stderr.on("data", (chunk) => {
    stderr += String(chunk);
  });
  const code = await new Promise<number | null>((resolve, reject) => {
    process.on("error", reject);
    process.on("close", resolve);
  });
  return { code, stdout, stderr };
}

describe("shared registry rendezvous", () => {
  it("retains literal dotted/numeric IDs and observed slot spelling", async () => {
    const f = await setup();
    const payload = JSON.parse(await readFile(f.consumer, "utf8"));
    for (const id of ["desk.alt", "007"]) {
      payload.id = id;
      const source = join(f.owner, `${id}.json`);
      await writeFile(source, JSON.stringify(payload));
      const destination = join(f.writable, `${id}.JSON.DISABLED`);
      await symlink(source, destination);
      const request = { domain: keybindingConsumers, policy: f.policy, source };
      expect(await register(request)).toMatchObject({
        id,
        destination,
        disposition: "current",
        participation: "disabled",
      });
      expect(lookup(await inspectRegistry(keybindingConsumers, f.policy), id).payload?.id).toBe(id);
    }
  });

  it("rejects special owner referents and malformed/unbound root policy", async () => {
    const f = await setup();
    const source = join(f.owner, "null.json");
    await symlink("/dev/null", source);
    await expect(
      register({ domain: keybindingProviders, policy: f.policy, source }),
    ).rejects.toThrow("regular file");
    await expect(
      inspectRegistry(keybindingConsumers, {
        scope: "user",
        roots: ["relative"],
        writeRoot: "relative",
      }),
    ).rejects.toThrow("absolute roots");
  });

  it("reports enabled:false from payload independently of active filename storage", async () => {
    const f = await setup();
    const request = { domain: keybindingConsumers, policy: f.policy, source: f.consumer };
    const first = await register(request);
    const value = JSON.parse(await readFile(f.consumer, "utf8"));
    value.enabled = false;
    await writeFile(f.consumer, JSON.stringify(value));
    expect(await register(request)).toMatchObject({
      destination: first.destination,
      participation: "disabled",
      disposition: "current",
    });
    const record = lookup(await inspectRegistry(keybindingConsumers, f.policy), "deck-main");
    expect(record.state).toBe("disabled");
    expect(record.source.state).toBe("active");
  });
  it("registers exact producer/consumer/Zim descriptors without centralizing payloads", async () => {
    const f = await setup();
    for (const [domain, source, id] of [
      [keybindingProviders, f.provider, "media-keys-main"],
      [keybindingConsumers, f.consumer, "deck-main"],
      [zimProviders, f.zim, "shell-tools"],
    ] as const) {
      const policy = explicitPolicy(
        "user",
        [join(f.root, domain.collection)],
        join(f.root, domain.collection),
      );
      // Each domain uses the same library without a shared payload union.
      const request = {
        domain: domain as
          | typeof keybindingProviders
          | typeof keybindingConsumers
          | typeof zimProviders,
        policy,
        source,
      };
      // The caller can erase the payload type when merely publishing a reference.
      const plan = await register<unknown>(request);
      expect(plan.disposition).toBe("create");
      expect(await readlink(plan.destination)).toBe(source);
      const material = join(f.root, "registration-material.json");
      await writeFile(material, JSON.stringify(plan.material));
      expect((await loadManifest(material)).manifest.links[0]?.src).toBe(source);
      const record = lookup(await inspectRegistry<unknown>(domain, policy), id);
      expect(record.state).toBe("active");
      expect(record.source.winner.referentPath).toBe(source);
      expect(await planRegistration<unknown>(request)).toMatchObject({ disposition: "current" });
    }
    expect(JSON.parse(await readFile(f.provider, "utf8")).resources).toEqual([
      { path: f.resource },
    ]);
  });

  it("retains disabled slots across owner reinstallation and source enabled changes", async () => {
    const f = await setup();
    const request = { domain: keybindingProviders, policy: f.policy, source: f.provider };
    const installed = await register(request);
    await rename(installed.destination, `${installed.destination}.disabled`);
    const next = await register(request);
    expect(next).toMatchObject({ disposition: "current", participation: "disabled" });
    expect(lookup(await inspectRegistry(keybindingProviders, f.policy), next.id).state).toBe(
      "disabled",
    );
    const payload = JSON.parse(await readFile(f.provider, "utf8"));
    payload.enabled = false;
    await writeFile(f.provider, JSON.stringify(payload));
    expect((await register(request)).participation).toBe("disabled");
    payload.enabled = true;
    await writeFile(f.provider, JSON.stringify(payload));
    expect((await register(request)).participation).toBe("disabled");
  });

  it("initially disabled manifests stay inert; enabled:false overrides remain operator-owned", async () => {
    const f = await setup();
    const value = JSON.parse(await readFile(f.consumer, "utf8"));
    value.enabled = false;
    await writeFile(f.consumer, JSON.stringify(value));
    const request = { domain: keybindingConsumers, policy: f.policy, source: f.consumer };
    expect(await register(request)).toMatchObject({
      destination: join(f.writable, "deck-main.json.disabled"),
      participation: "disabled",
    });
    await writeFile(join(f.overlay, "deck-main.json"), JSON.stringify(value));
    value.enabled = true;
    await writeFile(f.consumer, JSON.stringify(value));
    expect((await register(request)).participation).toBe("disabled");
    expect(
      lookup(await inspectRegistry(keybindingConsumers, f.policy), "deck-main").payload?.enabled,
    ).toBe(false);
  });

  it("mask veto is distinct, retains underlying disabled state and never unmasks", async () => {
    const f = await setup();
    const request = { domain: keybindingProviders, policy: f.policy, source: f.provider };
    const first = await register(request);
    await rename(first.destination, `${first.destination}.disabled`);
    const mask = join(f.overlay, "media-keys-main.json");
    await symlink("/dev/null", mask);
    const record = lookup(await inspectRegistry(keybindingProviders, f.policy), first.id);
    expect(record.state).toBe("masked");
    expect(record.source.observations).toHaveLength(2);
    expect(await register(request)).toMatchObject({
      disposition: "blocked",
      material: { links: [] },
    });
    expect(await readlink(mask)).toBe("/dev/null");
    // Deliberate operator removal, not a registry side effect.
    await rm(mask);
    expect(lookup(await inspectRegistry(keybindingProviders, f.policy), first.id).state).toBe(
      "disabled",
    );
  });

  it("preserves regular operator files and refuses other owners/slot collisions", async () => {
    const f = await setup();
    const slot = join(f.writable, "media-keys-main.json");
    await writeFile(slot, await readFile(f.provider));
    const request = { domain: keybindingProviders, policy: f.policy, source: f.provider };
    expect(await register(request)).toMatchObject({ disposition: "blocked" });
    await symlink(f.provider, `${slot}.disabled`);
    await expect(register(request)).rejects.toThrow("conflicting local");
    expect(await readFile(slot, "utf8")).toBe(await readFile(f.provider, "utf8"));
  });

  it("explains invalid payloads, identity mismatch, conflicts, and failed roots without fallback", async () => {
    const f = await setup();
    await symlink(f.provider, join(f.lower, "media-keys-main.json"));
    await writeFile(join(f.overlay, "media-keys-main.json"), "{bad-json}");
    expect(
      lookup(await inspectRegistry(keybindingProviders, f.policy), "media-keys-main"),
    ).toMatchObject({ state: "invalid", error: expect.any(String) });
    await writeFile(join(f.overlay, "wrong-id.json"), await readFile(f.provider));
    expect(
      lookup(await inspectRegistry(keybindingProviders, f.policy), "wrong-id").error,
    ).toContain("identity disagree");
    await symlink(f.provider, join(f.lower, "media-keys-main.json.disabled"));
    await rm(join(f.overlay, "media-keys-main.json"));
    expect(
      lookup(await inspectRegistry(keybindingProviders, f.policy), "media-keys-main").state,
    ).toBe("conflict");
    const failed = join(f.root, "not-directory");
    await writeFile(failed, "x");
    const policy = explicitPolicy("user", [f.lower, f.writable, failed], f.writable);
    const snapshot = await inspectRegistry(keybindingProviders, policy);
    expect(snapshot.complete).toBe(false);
    expect(snapshot.roots.at(-1)).toMatchObject({ status: "failed", error: { code: "ENOTDIR" } });
    expect(() => lookup(snapshot, "missing")).toThrow("incomplete registry");
    await expect(
      register({ domain: keybindingProviders, policy, source: f.provider }),
    ).rejects.toThrow("incompletely observed");
  });

  it("freezes exact observed membership, diagnoses retargeting, and aborts changed plans", async () => {
    const f = await setup();
    const request = { domain: keybindingProviders, policy: f.policy, source: f.provider };
    const first = await register(request);
    const view = await observe(f.policy.roots);
    await symlink(f.consumer, join(f.writable, "deck-main.json"));
    expect(view.entries.map((entry) => entry.identity)).toEqual(["media-keys-main"]);
    await rm(first.destination);
    await symlink(f.consumer, first.destination);
    await expect(load(view.entries[0]!)).rejects.toThrow("retargeted");
    await rm(first.destination);
    const plan = await planRegistration(request);
    await symlink("/dev/null", join(f.overlay, "media-keys-main.json"));
    await expect(applyRegistration(request, plan)).rejects.toThrow("changed since planning");
  });

  it("binds user XDG roots at invocation; explicit system policy ignores HOME", () => {
    expect(explicitPolicy("user", ["/lower", "/upper", "/lower"], "/lower").roots).toEqual([
      "/upper",
      "/lower",
    ]);
    const env = {
      HOME: "/isolated/home",
      XDG_DATA_HOME: "/isolated/data",
      XDG_CONFIG_HOME: "/isolated/config",
      XDG_DATA_DIRS: "/vendor:data-relative:/vendor",
      XDG_CONFIG_DIRS: "/site",
    };
    const user = registryPolicy("keybindings/consumers.d", "user", env);
    expect(user.writeRoot).toBe("/isolated/data/compfuzor/keybindings/consumers.d");
    expect(user.roots.at(-1)).toBe("/isolated/config/compfuzor/keybindings/consumers.mask.d");
    expect(
      user.roots.filter((root) => root === "/vendor/compfuzor/keybindings/consumers.d"),
    ).toHaveLength(1);
    env.HOME = "/changed";
    expect(user.writeRoot).toContain("/isolated/data");
    expect(
      registryPolicy("keybindings/consumers.d", "system", env).roots.some((root) =>
        root.includes("isolated"),
      ),
    ).toBe(false);
    expect(() => registryPolicy("zim/providers.d", "user", { HOME: "relative" })).toThrow();
  });

  it("runs Router registration/status/explain and tab completion through source/multicall entries", async () => {
    const f = await setup();
    const common = [
      "--collection",
      "keybinding-consumers",
      "--scope",
      "user",
      "--root",
      f.writable,
      "--root",
      f.overlay,
      "--write-root",
      f.writable,
    ];
    expect((await cli(["status", "--source", f.consumer, ...common])).code).toBe(1);
    expect((await cli(["register", "--source", f.consumer, ...common])).code).toBe(0);
    const status = await cli(["status", "--source", f.consumer, ...common, "--json"]);
    expect(status.code, status.stderr).toBe(0);
    expect(JSON.parse(status.stdout)).toMatchObject({ id: "deck-main", disposition: "current" });
    const listed = await cli(
      ["registry", "list", ...common, "--json"],
      "files/runtime/compfuzor-runtime.ts",
    );
    expect(listed.code, listed.stderr).toBe(0);
    expect(JSON.parse(listed.stdout).records[0].payload.adapter).toBe("niri");
    const explained = await cli(["explain", "deck-main", ...common, "--json"]);
    expect(JSON.parse(explained.stdout).source.winner.referentPath).toBe(f.consumer);
    const completion = await cli(["complete", ...common, "--word", "explain", "--word", ""]);
    expect(completion.code, completion.stderr).toBe(0);
    expect(completion.stdout).toContain("deck-main\tactive");
    expect((await cli(["list", ...common, "--typo"])).code).toBe(2);
    expect(
      (await cli(["list", "--collection", "keybinding-consumers", "--scope", "root"])).code,
    ).toBe(2);
    const help = await cli(["--help"]);
    expect(help.code).toBe(0);
    expect(help.stdout).toContain("no native installation");
  });
});
