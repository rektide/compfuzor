import { afterEach, expect, test } from "vitest";
import { chmod, copyFile, lstat, mkdir, mkdtemp, readFile, readlink, rm, symlink, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { assembleConsumer, consumerTemplate, type ConsumerOptions, type ConsumerRequest } from "../../files/config/keybindings/consumer.ts";
import { withInputBatch } from "../../files/config/registration.ts";
import type { Target } from "../../files/config/keybindings/model.ts";
import { shellQuote } from "../../files/config/keybindings/render.ts";

const repository = resolve(import.meta.dirname, "../..");
const scratch = join(repository, ".test-agent/keybindings-consumer");
const roots: string[] = [];
afterEach(async () => { await Promise.all(roots.splice(0).map((path) => rm(path, { recursive: true, force: true }))); });

async function fixture(target: Target): Promise<{ root: string; options: ConsumerOptions; copy: string; link: string; action: string }> {
  await mkdir(scratch, { recursive: true });
  await writeFile(join(scratch, "README.md"), "# Consumer assembly scratch\nIsolated native delivery, registration and candidate-closure validation fixtures.\n", { flag: "wx" }).catch((error: NodeJS.ErrnoException) => { if (error.code !== "EEXIST") throw error; });
  const root = await mkdtemp(join(scratch, `${target}-`));
  roots.push(root);
  const deployment = join(root, "deployment");
  await mkdir(join(deployment, "bin/config/processors"), { recursive: true });
  const runner = join(deployment, "bin/config/run.sh");
  await copyFile(join(repository, "files/config-run.sh"), runner);
  await chmod(runner, 0o755);
  const leaf = join(deployment, "bin/config/processors/concat");
  await writeFile(leaf, `#!/bin/bash\nexec bash ${shellQuote(join(repository, "files/config-processor.sh"))} concat "$@"\n`);
  await chmod(leaf, 0o755);
  const action = join(root, "nonidentity-action.yaml");
  const binding = join(root, "also-not-the-binding-ID.yaml");
  const linkedBinding = join(root, "other.yaml");
  await writeFile(action, "version: 1\nkind: action\nid: launcher\nexec: [echo, first]\n");
  await writeFile(binding, "version: 1\nkind: keybinding\nid: launch\naction: launcher\nkeys: [Mod+D]\n");
  await writeFile(linkedBinding, "version: 1\nkind: keybinding\nid: linked\naction: launcher\nkeys: [Mod+L]\n");
  const ext = target === "niri" ? "kdl" : "toml";
  const body = (key: string, command: string) => target === "niri" ? `binds { ${key} { spawn "echo" "${command}"; } }\n` : `[keybinds]\n"${key}" = "spawn:echo ${command}"\n`;
  const baseline = join(root, `baseline.${ext}`);
  const personal = join(root, `personal.${ext}`);
  await writeFile(baseline, body("Mod+B", "baseline"));
  await writeFile(personal, body("Mod+D", "personal"));
  const nativeDir = join(root, "native");
  await mkdir(nativeDir);
  const own = join(nativeDir, `own.${ext}`);
  await writeFile(join(nativeDir, `child.${ext}`), body("Mod+C", "child"));
  await writeFile(own, target === "niri" ? 'include "child.kdl"\nbinds { Mod+U { spawn "echo" "own"; } }\n' : '[include]\nfiles = ["child.toml"]\n[keybinds]\n"Mod+U" = "spawn:echo own"\n');
  const copy = join(root, `user/copied.${ext}`);
  const link = join(root, `user/linked.${ext}`);
  const request: ConsumerRequest = { version: 1, target, root: { path: join(root, `user/root.${ext}`) }, materialRoot: join(root, "materials"), yamlSources: [{ path: action }, { path: binding }, { path: linkedBinding }], nativeSources: [{ id: "own", path: own, format: target, order: 20, placement: { strategy: "direct" } }], bindings: { launch: { placement: { strategy: "copy", path: copy } }, linked: { placement: { strategy: "link", path: link } } }, baseline: [baseline], personal: [personal], mode: "seed" };
  const options: ConsumerOptions = { request, runner, validatorCommand: [process.execPath, join(repository, "files/config/keybindings/command.ts"), "validate"], workspaceRoot: scratch, stdio: "pipe" };
  return { root, options, copy, link, action };
}

for (const target of ["niri", "umbriel"] as const) {
  test(`${target}: direct own native sources, copy/link seed, edited-copy reassembly, refresh and failed prospective update`, async () => {
    const { root, options, copy, link, action } = await fixture(target);
    const request = options.request;
    request.mode = "assemble";
    await expect(assembleConsumer(options)).rejects.toThrow("selected user placement is missing");
    await expect(readFile(request.root.path)).rejects.toMatchObject({ code: "ENOENT" });
    request.mode = "seed";
    const checked = await assembleConsumer({ ...options, check: true });
    expect(checked.code, checked.stderr.toString()).toBe(1);
    await expect(readFile(copy)).rejects.toMatchObject({ code: "ENOENT" });
    const seeded = await assembleConsumer(options);
    expect(seeded.code, seeded.stderr.toString()).toBe(0);
    expect((await lstat(link)).isSymbolicLink()).toBe(true);
    expect(await readlink(link)).toBe(join(request.materialRoot, target, `linked.binding.${target === "niri" ? "kdl" : "toml"}`));
    const originalRoot = await readFile(request.root.path, "utf8");
    expect(originalRoot).toContain(copy);
    expect(originalRoot).toContain("keybinding/" + target + "/own start");
    expect(originalRoot).not.toContain("native-layout");
    if (target === "umbriel") expect(originalRoot.match(/\[include\]/g)).toHaveLength(1);
    const edited = target === "niri" ? 'binds { Mod+D { spawn "echo" "user-edited"; } }\n' : '[keybinds]\n"Mod+D" = "spawn:echo user-edited"\n';
    await writeFile(copy, edited);
    const unmanaged = target === "niri" ? "// keep my unrelated root text\n" : "# keep my unrelated root text\n";
    await writeFile(request.root.path, originalRoot + unmanaged);
    await writeFile(action, "version: 1\nkind: action\nid: launcher\nexec: [echo, second]\n");
    request.mode = "assemble";
    const updated = await assembleConsumer(options);
    expect(updated.code, updated.stderr.toString()).toBe(0);
    expect(await readFile(copy, "utf8")).toBe(edited);
    expect(await readFile(link, "utf8")).toContain("second");
    expect(await readFile(request.root.path, "utf8")).toContain(unmanaged);
    expect((await assembleConsumer({ ...options, check: true })).code).toBe(0);
    request.mode = "refresh";
    expect((await assembleConsumer(options)).code).toBe(0);
    expect(await readFile(copy, "utf8")).toContain("second");
    const before = new Map(await Promise.all(updated.outputs.map(async (path) => [path, await readFile(path, "utf8")] as const)));
    const oldLink = await readlink(link);
    await writeFile(action, `version: 1\nkind: action\nid: launcher\n${target}:\n  native: ${target === "niri" ? "{name: invented-invalid-action}" : "invented-invalid-action"}\n`);
    const failed = await assembleConsumer(options);
    expect(failed.code).not.toBe(0);
    expect(failed.stderr.toString()).toContain("transaction candidate validation failed");
    for (const [path, bytes] of before) expect(await readFile(path, "utf8"), path).toBe(bytes);
    expect(await readlink(link)).toBe(oldLink);
    await writeFile(action, "version: 1\nkind: action\nid: launcher\nexec: [echo, second]\n");
    // A path/order switch replaces the same contribution block, not a path-named
    // extra block. Former native files are deliberately not pruned.
    const switched = join(root, `own-switched.${target === "niri" ? "kdl" : "toml"}`);
    await writeFile(switched, target === "niri" ? 'binds { Mod+U { spawn "echo" "switched"; } }\n' : '[keybinds]\n"Mod+U" = "spawn:echo switched"\n');
    request.nativeSources![0] = { ...request.nativeSources![0], path: switched, order: -10 };
    expect((await assembleConsumer(options)).code).toBe(0);
    const switchedRoot = await readFile(request.root.path, "utf8");
    expect(switchedRoot.match(new RegExp(`keybinding/${target}/own start`, "g"))).toHaveLength(1);
    expect(switchedRoot).toContain(switched);
    expect(switchedRoot).not.toContain(join(root, "native/own."));
    expect(await readFile(join(root, "native/child." + (target === "niri" ? "kdl" : "toml")), "utf8")).toContain("child");
  }, 120000);
}

test("existing arbitrary Umbriel include table fails without adoption; explicit insertion area preserves unrelated TOML", async () => {
  const { root, options } = await fixture("umbriel");
  await mkdir(join(root, "user"));
  const raw = `[include]\nfiles = [${JSON.stringify(options.request.baseline![0])}]\n\n# unrelated existing configuration\n[general]\nautostart = []\n`;
  await writeFile(options.request.root.path, raw);
  await expect(assembleConsumer(options)).rejects.toThrow("adopted insertion area");
  expect(await readFile(options.request.root.path, "utf8")).toBe(raw);
  const adopted = consumerTemplate("umbriel", options.request.baseline!, options.request.personal!) + "\n# unrelated existing configuration\n[general]\nautostart = []\n";
  await writeFile(options.request.root.path, adopted);
  const result = await assembleConsumer(options);
  expect(result.code, result.stderr.toString()).toBe(0);
  const assembled = await readFile(options.request.root.path, "utf8");
  expect(assembled).toContain("[general]\nautostart = []\n");
  expect(assembled.match(/\[include\]/g)).toHaveLength(1);
  options.request.root.area = { begin: "# wrong begin", end: "# wrong end" };
  await writeFile(options.request.root.path, adopted.replace("# compfuzor-keybindings-begin", "# other").replace("# compfuzor-keybindings-end", "# other-end") + '# wrong begin\n# wrong end\n');
  await expect(assembleConsumer(options)).rejects.toThrow("inside Umbriel include.files");
}, 120000);

test("Niri direct/copy inline uses the same source interface and rebinds relative includes to selected placement", async () => {
  const { root, options } = await fixture("niri");
  options.request.yamlSources = [];
  options.request.bindings = {};
  options.request.nativeSources![0].incorporation = "inline";
  const direct = await assembleConsumer(options);
  expect(direct.code, direct.stderr.toString()).toBe(0);
  let text = await readFile(options.request.root.path, "utf8");
  expect(text).toContain(`include "${root}/native/child.kdl"`);
  expect(text).toContain('spawn "echo" "own"');
  expect(direct.outputs.some((path) => path.endsWith("own.inline.kdl"))).toBe(true);
  const copied = join(root, "user/copied-native.kdl");
  await writeFile(join(root, "user/child.kdl"), 'binds { Mod+C { spawn "echo" "local-child"; } }\n');
  options.request.nativeSources![0].placement = { strategy: "copy", path: copied };
  const installed = await assembleConsumer(options);
  expect(installed.code, installed.stderr.toString()).toBe(0);
  text = await readFile(options.request.root.path, "utf8");
  expect(text).toContain(`include "${root}/user/child.kdl"`);
  expect(text).not.toContain(`include "${root}/native/child.kdl"`);
  await writeFile(copied, 'binds { Mod+U { spawn "echo" "edited-copy"; } }\n');
  options.request.mode = "assemble";
  expect((await assembleConsumer(options)).code).toBe(0);
  expect(await readFile(options.request.root.path, "utf8")).toContain("edited-copy");
  const previousRoot = await readFile(options.request.root.path, "utf8");
  await rm(options.request.nativeSources![0].path);
  expect((await assembleConsumer(options)).code).toBe(0); // No producer fallback or dependency for an edited local copy.
  await rm(copied);
  await expect(assembleConsumer(options)).rejects.toThrow("selected user placement is missing");
  expect(await readFile(options.request.root.path, "utf8")).toBe(previousRoot);
}, 120000);

test("root revision guard preserves a concurrent user's edit instead of publishing stale root/material candidates", async () => {
  const { root, options, action } = await fixture("niri");
  options.request.yamlSources = [];
  options.request.bindings = {};
  const installed = await assembleConsumer(options);
  expect(installed.code, installed.stderr.toString()).toBe(0);
  const old = await readFile(options.request.root.path, "utf8");
  const companion = installed.outputs.find((path) => path.endsWith("own.include.kdl"))!;
  const oldCompanion = await readFile(companion, "utf8");
  // This simulates another actor, not a mutation by a processor.
  const script = join(root, "concurrent-validator.sh");
  await writeFile(script, `#!/bin/bash\nprintf '\\n// concurrent user edit\\n' >> ${shellQuote(options.request.root.path)}\nexec ${shellQuote(process.execPath)} ${shellQuote(join(repository, "files/config/keybindings/command.ts"))} validate "$@"\n`);
  await chmod(script, 0o755);
  await writeFile(action, "version: 1\nkind: action\nid: launcher\nexec: [echo, changed]\n");
  const rejected = await assembleConsumer({ ...options, validatorCommand: [script] });
  expect(rejected.code).not.toBe(0);
  expect(rejected.stderr.toString()).toContain("changed since capture");
  expect(await readFile(options.request.root.path, "utf8")).toBe(old + "\n// concurrent user edit\n");
  expect(await readFile(companion, "utf8")).toBe(oldCompanion);
}, 120000);

test("normalized and directory-symlink placement aliases are rejected before output writes", async () => {
  const { root, options } = await fixture("niri");
  options.request.yamlSources = [];
  options.request.bindings = {};
  const source = options.request.nativeSources![0];
  options.request.nativeSources!.push({ ...source, id: "other", path: join(root, "native/../native/own.kdl") });
  await expect(assembleConsumer(options)).rejects.toThrow("claim placement");
  await expect(readFile(options.request.root.path)).rejects.toMatchObject({ code: "ENOENT" });
  await symlink(join(root, "native"), join(root, "alias"));
  options.request.nativeSources![1].path = join(root, "alias/own.kdl");
  await expect(assembleConsumer(options)).rejects.toThrow("physical placement");
});

test("registration updates action/binding once as a batch; failed closure restores prior links and disabled state", async () => {
  const { root, options } = await fixture("niri");
  options.request.yamlSources = options.request.yamlSources!.slice(0, 2);
  options.request.bindings = { launch: options.request.bindings!.launch };
  const registry = join(root, "registry");
  await mkdir(registry);
  const priorAction = options.request.yamlSources![0].path;
  const priorBinding = options.request.yamlSources![1].path;
  const action = join(registry, "action.yaml");
  const binding = join(registry, "binding.yaml");
  await symlink(priorAction, action);
  await symlink(priorBinding, binding);
  options.request.yamlSources = [{ path: action, disabledSuffix: ".disabled" }, { path: binding, disabledSuffix: ".disabled" }];
  expect((await assembleConsumer(options)).code).toBe(0);
  const oldRoot = await readFile(options.request.root.path, "utf8");
  const bad = join(root, "bad-action.yaml");
  await writeFile(bad, "version: 1\nkind: action\nid: launcher\nniri: {native: {name: invented-invalid-action}}\n");
  let calls = 0;
  const result = await withInputBatch([
    { source: bad, destination: action, strategy: "link", disabledSuffix: ".disabled" },
    { source: priorBinding, destination: binding, strategy: "link", disabledSuffix: ".disabled" },
  ], async () => { calls++; expect(await readlink(action)).toBe(bad); expect(await readlink(binding)).toBe(priorBinding); return assembleConsumer(options); }, { success: (value) => value.code === 0, workspaceRoot: scratch });
  expect(calls).toBe(1);
  expect(result.code).not.toBe(0);
  expect(await readlink(action)).toBe(priorAction);
  expect(await readlink(binding)).toBe(priorBinding);
  expect(await readFile(options.request.root.path, "utf8")).toBe(oldRoot);
  await rm(binding);
  await symlink(priorBinding, binding + ".disabled");
  const disabled = await withInputBatch([
    { source: priorAction, destination: action, strategy: "copy", disabledSuffix: ".disabled" },
    { source: priorBinding, destination: binding, strategy: "link", disabledSuffix: ".disabled" },
  ], async (inputs) => { expect(inputs[1].disabled).toBe(true); expect(await readlink(binding + ".disabled")).toBe(priorBinding); return assembleConsumer(options); }, { success: (value) => value.code === 0, workspaceRoot: scratch });
  expect(disabled.code, disabled.stderr.toString()).toBe(0);
  expect(await readlink(binding + ".disabled")).toBe(priorBinding);
  await expect(lstat(binding)).rejects.toMatchObject({ code: "ENOENT" });
  expect(await readFile(options.request.root.path, "utf8")).not.toContain("keybinding/niri/launch start");
}, 120000);
