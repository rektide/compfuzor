import { afterEach, expect, it, vi } from "vitest";
import { mkdir, readFile, readlink, rename, rm, symlink, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fixtures } from "./fixtures.ts";
import { register } from "../../runtime/registry/register.ts";
import { keybindingConsumers } from "../../runtime/keybindings/registry.ts";
import { registryPolicy } from "../../runtime/registry/policy.ts";
import {
  admitKeybindingBatch,
  runAdmittedKeybindingBatch,
} from "../../runtime/keybindings/invocation.ts";
import { admitKeybindingCommand } from "../../files/config/keybindings/runtime.ts";
import { verifyPreparedOperation } from "../../files/actions/operations.ts";
import type { KeybindingBatchStep } from "../../files/actions/model.ts";
import * as registration from "../../runtime/registry/register.ts";
import * as capture from "../../files/config/capture.ts";

const roots: string[] = [];
afterEach(async () => {
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});
const defaults = {
  runner: resolve("files/config-run.sh"),
  validatorCommand: [
    process.execPath,
    resolve("files/runtime/compfuzor-runtime.ts"),
    "keybindings",
    "validate",
  ],
};

it("admits an explicitly packaged prospective receiver without publishing during admission", async () => {
  const f = await setup();
  await rm(join(f.policy.writeRoot, "deck-main.json"));
  const selection = join(f.owner, "selection.json");
  await writeFile(
    selection,
    JSON.stringify({
      version: 1,
      receivers: [{ id: "deck-main" }],
      prospectiveConsumers: { user: [{ relative: "deck-main.json" }] },
    }),
  );
  const batch = await admitKeybindingBatch({ args: [], manifest: f.provider, selection, defaults });
  expect(batch.members.map((entry) => entry.id)).toEqual(["deck-main"]);
  await expect(readFile(join(f.policy.writeRoot, "deck-main.json"))).rejects.toThrow();
  await register({
    domain: keybindingConsumers,
    policy: f.policy,
    source: join(f.owner, "deck-main.json"),
  });
  await import("../../runtime/registry/guard.ts").then(({ assertRegistryGuards }) =>
    assertRegistryGuards([batch.members[0]!.registry]),
  );
});

it("filters authored mixed-audience IDs before lookup and rejects explicit outside-audience requests", async () => {
  const f = await setup(),
    selection = join(f.owner, "selection.json");
  await writeFile(
    selection,
    JSON.stringify({
      version: 1,
      receivers: [
        { id: "deck-main", scope: "user" },
        { id: "not-in-user-registry", scope: "system" },
      ],
    }),
  );
  const request = { args: [], manifest: f.provider, selection, defaults };
  expect((await admitKeybindingBatch(request)).members.map((entry) => entry.id)).toEqual([
    "deck-main",
  ]);
  await expect(
    admitKeybindingBatch({ ...request, args: ["--target", "not-in-user-registry"] }),
  ).rejects.toThrow("outside invocation audience");
});

it("rejects operative producer redirects and does not bless a mask inserted after publication", async () => {
  const f = await setup();
  const providerPolicy = registryPolicy("keybindings/providers.d", "user");
  const overlay = providerPolicy.roots.at(-1)!;
  await mkdir(overlay, { recursive: true });
  const redirected = JSON.parse(await readFile(f.provider, "utf8"));
  redirected.order += 1;
  const path = join(overlay, "media-keys-main.json");
  await writeFile(path, JSON.stringify(redirected));
  const request = { args: ["--target", "deck-main"], manifest: f.provider, defaults };
  await expect(admitKeybindingBatch(request)).rejects.toThrow(
    "redirects the owned operative offer",
  );
  await rm(path);
  const batch = await admitKeybindingBatch(request),
    original = registration.applyRegistration;
  vi.spyOn(registration, "applyRegistration").mockImplementation(async (request, plan) => {
    const result = await original(request, plan);
    await symlink("/dev/null", path);
    return result;
  });
  await expect(runAdmittedKeybindingBatch(batch)).rejects.toThrow("registration changed");
  await expect(readFile(batch.members[0]!.admitted.bound.statePath)).rejects.toThrow();
});

it("selection decoding and its guard refer to the same captured bytes across an intervening edit", async () => {
  const f = await setup(),
    selection = join(f.owner, "selection.json");
  await writeFile(selection, JSON.stringify({ version: 1, receivers: [{ id: "deck-main" }] }));
  const original = capture.captureFile;
  vi.spyOn(capture, "captureFile").mockImplementation(async (path) => {
    const captured = await original(path);
    if (path === selection)
      await writeFile(selection, JSON.stringify({ version: 1, receivers: [] }));
    return captured;
  });
  const batch = await admitKeybindingBatch({ args: [], manifest: f.provider, selection, defaults });
  expect(batch.members.map((entry) => entry.id)).toEqual(["deck-main"]);
  await expect(runAdmittedKeybindingBatch(batch)).rejects.toThrow("source changed");
});
async function setup() {
  const f = await fixtures();
  roots.push(f.root);
  for (const [name, value] of Object.entries({
    HOME: f.root,
    XDG_DATA_HOME: join(f.root, "xdg-data"),
    XDG_CONFIG_HOME: join(f.root, "xdg-config"),
    XDG_DATA_DIRS: join(f.root, "vendor-data"),
    XDG_CONFIG_DIRS: join(f.root, "site-config"),
  }))
    vi.stubEnv(name, value);
  const policy = registryPolicy(keybindingConsumers.collection, "user");
  const one = join(f.owner, "one.json"),
    two = join(f.owner, "two.json");
  for (const [id, profile] of [
    ["desk.one", one],
    ["deck-main", two],
  ]) {
    await writeFile(
      profile!,
      JSON.stringify({
        version: 1,
        target: "niri",
        contexts: { user: { scope: "user", root: { path: join(f.root, id!) } } },
        baseline: [],
        personal: [],
      }),
    );
    const source = join(f.owner, `${id}.json`);
    await writeFile(
      source,
      JSON.stringify({
        version: 1,
        id,
        adapter: "niri",
        audience: "user",
        profile: { path: profile },
        contexts: ["user"],
        defaultContext: "user",
      }),
    );
    await register({ domain: keybindingConsumers, source, policy });
  }
  return { ...f, policy };
}

it("defaults to all enabled compatible receivers, admits explicit subsets and serializes force policy", async () => {
  const f = await setup();
  const request = { args: [], manifest: f.provider, defaults };
  const all = await admitKeybindingBatch(request);
  expect(all.members.map((entry) => entry.id)).toEqual(["deck-main", "desk.one"]);
  expect(all.members.every((entry) => entry.admitted.options.profile.target === "niri")).toBe(true);
  await rename(
    join(f.policy.writeRoot, "deck-main.json"),
    join(f.policy.writeRoot, "deck-main.json.disabled"),
  );
  expect((await admitKeybindingBatch(request)).members.map((entry) => entry.id)).toEqual([
    "desk.one",
  ]);
  await expect(
    admitKeybindingBatch({ ...request, args: ["--target", "deck-main"] }),
  ).rejects.toThrow("--force-enable");
  const forced = await admitKeybindingBatch({
    ...request,
    args: ["--force-enable", "--target", "deck-main"],
  });
  expect(forced).toMatchObject({
    forceEnable: true,
    members: [{ id: "deck-main", originalState: "disabled", forced: true }],
  });
  const serialized = JSON.parse(JSON.stringify(forced));
  const step: KeybindingBatchStep = {
    kind: "domain",
    id: "install",
    domain: "keybindings",
    operation: "install-offer",
    envelope: "bin/install-keybindings.sh",
    manifest: f.provider,
    producer: "media-keys-main",
  };
  verifyPreparedOperation({ domain: "keybindings-batch", admitted: serialized }, step, "user");
  serialized.forceEnable = false;
  expect(() =>
    verifyPreparedOperation({ domain: "keybindings-batch", admitted: serialized }, step, "user"),
  ).toThrow();
  expect(await readlink(join(f.policy.writeRoot, "deck-main.json.disabled"))).toBe(
    join(f.owner, "deck-main.json"),
  );
  const defaultForced = await admitKeybindingBatch({ ...request, args: ["--force-enable"] });
  expect(defaultForced.members).toHaveLength(2);
  const masks = f.policy.roots.at(-1)!;
  await mkdir(masks, { recursive: true });
  await symlink("/dev/null", join(masks, "deck-main.json"));
  expect(
    (await admitKeybindingBatch({ ...request, args: ["--force-enable"] })).members.map(
      (entry) => entry.id,
    ),
  ).toEqual(["desk.one"]);
  await expect(
    admitKeybindingBatch({ ...request, args: ["--force-enable", "--target", "deck-main"] }),
  ).rejects.toThrow("masked");
});

it("guards admission before effects and does not widen membership for later registrations", async () => {
  const f = await setup();
  const batch = await admitKeybindingBatch({
    args: ["--target", "deck-main"],
    manifest: f.provider,
    defaults,
  });
  const overlay = f.policy.roots.at(-1)!;
  await mkdir(overlay, { recursive: true });
  await symlink("/dev/null", join(overlay, "deck-main.json"));
  await expect(runAdmittedKeybindingBatch(batch)).rejects.toThrow("selected registration changed");
  expect(batch.members.map((entry) => entry.id)).toEqual(["deck-main"]);
  await expect(readFile(batch.publication.plan.destination)).rejects.toThrow();
});

it("admission applies enabled:false only at receiver registration level and retains selectors", async () => {
  const f = await setup();
  const descriptor = join(f.owner, "deck-main.json");
  const data = JSON.parse(await readFile(descriptor, "utf8"));
  data.enabled = false;
  data.profile = {
    env: "CUSTOM_PROFILE",
    ignore: ["none"],
    default: { path: "${HOME}/owners/two.json" },
  };
  await writeFile(descriptor, JSON.stringify(data));
  const batch = await admitKeybindingBatch({
    args: ["--target", "deck-main", "--force-enable"],
    manifest: f.provider,
    defaults,
  });
  expect(batch.members[0]?.forced).toBe(true);
  expect(JSON.parse(await readFile(descriptor, "utf8")).enabled).toBe(false);
  await expect(
    admitKeybindingCommand("host", ["--descriptor", descriptor, "--scope", "user"], defaults),
  ).rejects.toThrow("--force-enable");
  const host = await admitKeybindingCommand(
    "host",
    ["--descriptor", descriptor, "--scope", "user", "--force-enable"],
    defaults,
  );
  expect(host.registrySelection).toMatchObject({
    id: "deck-main",
    originalState: "disabled",
    forceEnable: true,
  });
  data.profile = { env: "CUSTOM_PROFILE", ignore: ["none"], default: { relative: "two.json" } };
  await writeFile(descriptor, JSON.stringify(data));
  const relative = await admitKeybindingBatch({
    args: ["--target", "deck-main", "--force-enable"],
    manifest: f.provider,
    defaults,
  });
  expect(relative.members[0]?.admitted.options.profileGuard?.path).toBe(join(f.owner, "two.json"));
});

it("explicit empty declaration stays no-delivery and CLI cannot widen a declared subset", async () => {
  const f = await setup();
  const selection = join(f.owner, "selection.json");
  await writeFile(selection, JSON.stringify({ version: 1, receivers: [] }));
  const request = { args: [], manifest: f.provider, selection, defaults };
  expect((await admitKeybindingBatch(request)).members).toEqual([]);
  await expect(
    admitKeybindingBatch({ ...request, args: ["--target", "deck-main"] }),
  ).rejects.toThrow("outside declared");
});
