import { afterEach, expect, test, vi } from "vitest";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  admitKeybindingCommand,
  type KeybindingActionBinding,
} from "../../files/config/keybindings/runtime.ts";
import type { Profile } from "../../files/config/keybindings/membership.ts";

const roots: string[] = [];
const defaults = { runner: "/declared/runner", validatorCommand: ["declared-validator"] };
const binding: KeybindingActionBinding = {
  command: "host",
  target: "niri",
  audience: "user",
  context: "desktop",
  mode: "assemble",
};
afterEach(async () => {
  vi.unstubAllEnvs();
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

async function fixture() {
  const scratch = resolve(".test-agent/action-audiences");
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(join(scratch, "keybinding-admission-"));
  roots.push(root);
  const profile: Profile = {
    version: 1,
    target: "niri",
    contexts: {
      desktop: { scope: "user", root: { path: join(root, "desktop") } },
      laptop: { scope: "user", root: { path: join(root, "laptop") } },
      host: { scope: "system", root: { path: join(root, "host") } },
    },
  };
  const path = join(root, "profile.json");
  await writeFile(path, JSON.stringify(profile));
  return { root, profile, path };
}

test("keybinding admission binds arbitrary same-audience contexts and rejects scope, target, mode and profile escapes", async () => {
  const { path, profile, root } = await fixture();
  const args = ["--profile", path];
  const initial = await admitKeybindingCommand("host", args, defaults, binding);
  expect(initial.bound.base).toBe(join(root, "desktop"));
  expect(initial.options.mode).toBe("assemble");
  expect(
    (await admitKeybindingCommand("host", [...args, "--context", "laptop"], defaults, binding))
      .bound.base,
  ).toBe(join(root, "laptop"));
  await expect(
    admitKeybindingCommand("host", [...args, "--context", "host"], defaults, binding),
  ).rejects.toThrow("generated user scope");
  await expect(
    admitKeybindingCommand(
      "host",
      [...args, "--scope", "system", "--context", "host"],
      defaults,
      binding,
    ),
  ).rejects.toThrow("selected user audience");
  await expect(
    admitKeybindingCommand("host", [...args, "--target", "umbriel"], defaults, binding),
  ).rejects.toThrow("target does not match declared");
  await expect(
    admitKeybindingCommand("host", [...args, "--mode", "seed"], defaults, binding),
  ).rejects.toThrow("must remain assemble");
  profile.contexts.desktop.scope = "system";
  await writeFile(path, JSON.stringify(profile));
  await expect(admitKeybindingCommand("host", args, defaults, binding)).rejects.toThrow(
    "generated user scope",
  );
  await expect(readFile(join(root, "desktop/config.kdl"))).rejects.toMatchObject({
    code: "ENOENT",
  });
});

test("external environment profile selectors are preserved, but their effective context must match the audience", async () => {
  const { path, profile } = await fixture();
  const args = ["--profile-selector", JSON.stringify({ env: "TEST_ACTION_CONSUMER_PROFILE" })];
  vi.stubEnv("TEST_ACTION_CONSUMER_PROFILE", path);
  expect(
    (await admitKeybindingCommand("host", args, defaults, binding)).options.profile.target,
  ).toBe("niri");
  profile.contexts.desktop.scope = "system";
  await writeFile(path, JSON.stringify(profile));
  await expect(admitKeybindingCommand("host", args, defaults, binding)).rejects.toThrow(
    "generated user scope",
  );
});

test("producer identity and registration lifecycle stay distinct from host assembly", async () => {
  const { path, root } = await fixture();
  const manifest = join(root, "producer.json");
  await writeFile(
    manifest,
    JSON.stringify({ version: 1, producer: "media", order: 100, targets: ["niri"], resources: [] }),
  );
  const producer: KeybindingActionBinding = {
    command: "install",
    target: "niri",
    audience: "user",
    context: "desktop",
    producer: "media",
  };
  const args = ["--profile", path, "--manifest", manifest];
  const admitted = await admitKeybindingCommand("install", args, defaults, producer);
  expect(admitted.manifest?.producer).toBe("media");
  await expect(
    admitKeybindingCommand("install", [...args, "--check"], defaults, producer),
  ).rejects.toThrow("explicit mutation");
  await expect(admitKeybindingCommand("install", args, defaults, binding)).rejects.toThrow(
    "command does not match declared",
  );
  await writeFile(
    manifest,
    JSON.stringify({
      version: 1,
      producer: "different",
      order: 100,
      targets: ["niri"],
      resources: [],
    }),
  );
  await expect(admitKeybindingCommand("install", args, defaults, producer)).rejects.toThrow(
    "producer manifest does not match declared",
  );
  await expect(readFile(join(root, "desktop/.keybindings/membership.json"))).rejects.toMatchObject({
    code: "ENOENT",
  });
});

test("raw CLI still requires target and defaults host delivery to seed; admitted binding can be serialized", async () => {
  const { path, root } = await fixture();
  await expect(admitKeybindingCommand("host", ["--profile", path], defaults)).rejects.toThrow(
    "explicit --target",
  );
  const raw = await admitKeybindingCommand(
    "host",
    ["--profile", path, "--target", "niri", "--context", "desktop"],
    defaults,
  );
  expect(raw.options.mode).toBe("seed");
  const prepared = await admitKeybindingCommand("host", ["--profile", path], defaults, binding);
  await writeFile(path, "changed profile selection");
  expect(JSON.parse(JSON.stringify(prepared)).bound.request.root.path).toBe(
    join(root, "desktop/config.kdl"),
  );
});
