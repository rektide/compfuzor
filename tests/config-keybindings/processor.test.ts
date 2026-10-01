import { afterEach, expect, test } from "vitest";
import { execFile } from "node:child_process";
import {
  chmod,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
import { runAssemblyResult } from "../../files/config/assembly.ts";
import type { ConfigSpec } from "../../files/config/context.ts";
import { decodeContribution } from "../../files/config/keybindings/decode.ts";
import { compose } from "../../files/config/keybindings/model.ts";
import { selectMaterials, renderRoot } from "../../files/config/keybindings/materials.ts";
import { projectionRecipes } from "../../files/config/keybindings/recipes.ts";
import { shellQuote, renderDefinition } from "../../files/config/keybindings/render.ts";

const exec = promisify(execFile);
const repository = resolve(import.meta.dirname, "../..");
const scratch = join(repository, ".test-agent/keybindings");
const temporary: string[] = [];
afterEach(async () => {
  await Promise.all(temporary.splice(0).map((path) => rm(path, { recursive: true, force: true })));
});

async function fixture(): Promise<string> {
  await mkdir(scratch, { recursive: true });
  await writeFile(
    join(scratch, "README.md"),
    "# Keybinding scratch\n\nIsolated tests create disposable consumer layouts here. No live compositor configuration is edited.\n",
    { flag: "wx" },
  ).catch((error: NodeJS.ErrnoException) => {
    if (error.code !== "EEXIST") throw error;
  });
  const root = await mkdtemp(join(scratch, "consumer-"));
  temporary.push(root);
  return root;
}

test("current runner renders all single-output materials; check/stdout and invalid updates do not publish", async () => {
  const root = await fixture();
  const etc = join(root, "etc");
  const actionPath = join(etc, "action/launcher.yaml");
  const bindingPath = join(etc, "keybinding/launch.yaml");
  await Promise.all([
    mkdir(join(etc, "action"), { recursive: true }),
    mkdir(join(etc, "keybinding"), { recursive: true }),
    mkdir(join(root, "bin/internal/config"), { recursive: true }),
    mkdir(join(root, "bin/config"), { recursive: true }),
  ]);
  await writeFile(actionPath, "version: 1\nkind: action\nid: launcher\nexec: [vicinae, toggle]\n");
  await writeFile(
    bindingPath,
    "version: 1\nkind: keybinding\nid: launch\naction: launcher\nkeys: [Mod+D]\n",
  );
  const composition = compose(
    [
      decodeContribution(
        { version: 1, kind: "action", id: "launcher", exec: ["vicinae", "toggle"] },
        actionPath,
      ),
      decodeContribution(
        { version: 1, kind: "keybinding", id: "launch", action: "launcher", keys: ["Mod+D"] },
        bindingPath,
      ),
    ],
    "niri",
  );
  const projected = projectionRecipes(composition, [actionPath, bindingPath], etc);
  const configs: ConfigSpec["configs"] = {};
  const consumerConfigs: NonNullable<ConfigSpec["contexts"]>[string]["configs"] = {};
  const consumer = join(root, "user");
  for (const [output, recipe] of Object.entries(projected.recipes)) {
    const leaf = join(root, "bin/internal/config", recipe.name);
    const fixed = recipe.processor.args.map(shellQuote).join(" ");
    await writeFile(
      leaf,
      `#!/bin/bash\nexec ${shellQuote(process.execPath)} ${shellQuote(join(repository, "files/config/keybindings/command.ts"))} ${fixed} "$@"\n`,
    );
    await chmod(leaf, 0o755);
    configs[recipe.name] = { ...recipe, output, apply: true };
    consumerConfigs[recipe.name] = {
      output: { path: output.replace(etc, consumer) },
      inputs: recipe.inputs.map((input) => ({
        path: recipe.name.endsWith("-include") ? input.file.replace(etc, consumer) : input.file,
      })),
    };
  }
  const spec: ConfigSpec = {
    version: 2,
    defaultContext: "user",
    configs,
    contexts: { user: { scope: "user", root: { path: consumer }, configs: consumerConfigs } },
  };
  const runner = join(root, "bin/config/run.sh");
  await copyFile(join(repository, "files/config-run.sh"), runner);
  await chmod(runner, 0o755);
  const options = {
    spec,
    contextName: "user",
    runner,
    names: Object.keys(configs),
    stdio: "pipe" as const,
  };
  const definition = join(consumer, "niri/launch.binding.kdl");
  const inclusion = join(consumer, "niri/launch.include.kdl");
  const preview = await runAssemblyResult({
    ...options,
    names: ["keybinding-niri-launch-definition"],
    stdout: true,
  });
  expect(preview.code, preview.stderr.toString()).toBe(0);
  expect(preview.stdout.toString()).toContain('spawn "vicinae" "toggle";');
  await expect(readFile(definition)).rejects.toMatchObject({ code: "ENOENT" });
  expect((await runAssemblyResult({ ...options, check: true, quiet: true })).code).toBe(1);
  const installed = await runAssemblyResult(options);
  expect(installed.code, installed.stderr.toString()).toBe(0);
  expect(await readFile(inclusion, "utf8")).toBe(`include ${JSON.stringify(definition)}\n`);
  expect(await readFile(inclusion, "utf8")).not.toContain(etc);
  expect((await runAssemblyResult({ ...options, check: true, quiet: true })).code).toBe(0);
  await writeFile(actionPath, "version: 1\nkind: action\nid: launcher\nexec: [updated, --one]\n");
  expect((await runAssemblyResult(options)).code).toBe(0);
  const updated = await readFile(definition, "utf8");
  expect(updated).toContain('spawn "updated" "--one";');
  await writeFile(
    bindingPath,
    "version: 1\nkind: keybinding\nid: launch\naction: absent\nkeys: [Mod+D]\n",
  );
  const rejected = await runAssemblyResult(options);
  expect(rejected.code).not.toBe(0);
  expect(rejected.stderr.toString()).toContain("unresolved action absent");
  expect(await readFile(definition, "utf8")).toBe(updated);
}, 30000);

test("deployed bundled processor works outside the checkout without source or node_modules", async () => {
  const root = await fixture();
  await copyFile(
    join(repository, "runtime/compfuzor-runtime.mjs"),
    join(root, "compfuzor-runtime.mjs"),
  );
  await symlink("compfuzor-runtime.mjs", join(root, "keybinding-processor.mjs"));
  const native = join(root, "own.toml");
  await writeFile(native, '[keybinds]\n"Mod+F" = "window-close"\n');
  const manifest = join(root, "inputs");
  const candidate = join(root, "candidate");
  const spec = join(root, "spec.json");
  await writeFile(manifest, `file\tfile/0/own.toml\t${native}\t{}\n`);
  await writeFile(spec, JSON.stringify({ configs: { own: { output: candidate } } }));
  const env = {
    ...process.env,
    CONFIG_SPEC: spec,
    CONFIG_TRANSACTION: root,
    CONFIG_CANDIDATE: candidate,
    CONFIG_INPUTS_FILE: manifest,
  };
  const result = await exec(
    process.execPath,
    [
      join(root, "keybinding-processor.mjs"),
      "--config",
      "own",
      "--target",
      "umbriel",
      "--material",
      "include",
    ],
    { cwd: root, env },
  );
  expect(result.stdout).toBe("");
  expect(await readFile(candidate, "utf8")).toBe(`${JSON.stringify(native)},\n`);
  // Definition decoding also exercises the bundled YAML dependency.
  const action = join(root, "action.yaml");
  const binding = join(root, "binding.yaml");
  await writeFile(action, "version: 1\nkind: action\nid: launch\nexec: [echo, ok]\n");
  await writeFile(
    binding,
    "version: 1\nkind: keybinding\nid: launch\naction: launch\nkeys: [Mod+D]\n",
  );
  await writeFile(
    manifest,
    `file\tfile/0/action.yaml\t${action}\t{}\nfile\tfile/1/binding.yaml\t${binding}\t{}\n`,
  );
  await exec(
    process.execPath,
    [
      join(root, "keybinding-processor.mjs"),
      "--config",
      "own",
      "--target",
      "umbriel",
      "--material",
      "definition",
      "--binding",
      "launch",
    ],
    { cwd: root, env },
  );
  expect(await readFile(candidate, "utf8")).toContain("spawn:'echo' 'ok'");
});

for (const target of ["niri", "umbriel"] as const) {
  test(`native ${target} validator checks a complete isolated candidate include layout`, async ({
    skip,
  }) => {
    const root = await fixture();
    const action = decodeContribution(
      { version: 1, kind: "action", id: "launch", exec: ["echo", "a'b", "$(bad)"] },
      "action.yaml",
    );
    const binding = decodeContribution(
      {
        version: 1,
        kind: "keybinding",
        id: "launch",
        action: "launch",
        keys: ["Mod+D"],
        options: { repeat: false },
      },
      "binding.yaml",
    );
    const resolved = compose([action, binding], target).bindings[0];
    const extension = target === "niri" ? "kdl" : "toml";
    const fragment = join(root, `candidate.${extension}`);
    const config = join(root, `root.${extension}`);
    await writeFile(fragment, renderDefinition(resolved, target));
    const workspace = compose(
      [
        decodeContribution(
          {
            version: 1,
            kind: "action",
            id: "workspace",
            niri: { native: { name: "focus-workspace", args: [2] } },
            umbriel: { native: "workspace-switch:2" },
          },
          "workspace-action.yaml",
        ),
        decodeContribution(
          { version: 1, kind: "keybinding", id: "workspace", action: "workspace", keys: ["Mod+2"] },
          "workspace-binding.yaml",
        ),
      ],
      target,
    ).bindings[0];
    const workspaceFragment = join(root, `workspace.${extension}`);
    await writeFile(workspaceFragment, renderDefinition(workspace, target));
    const selected = selectMaterials(target, [
      { id: "launch", path: fragment, format: target, order: 0, placement: { strategy: "direct" } },
      {
        id: "workspace",
        path: workspaceFragment,
        format: target,
        order: 10,
        placement: { strategy: "direct" },
      },
    ]);
    await writeFile(config, renderRoot(target, selected, []));
    // This is optional only on hosts that do not have the compositor validator.
    try {
      await exec(
        target,
        target === "niri" ? ["validate", "--config", config] : ["validate", "-c", config],
      );
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") skip();
      throw error;
    }
    await writeFile(
      fragment,
      target === "niri"
        ? "binds { Mod+D { invented-invalid-action; } }\n"
        : '[keybinds]\n"Mod+D" = "invented-invalid-action"\n',
    );
    await expect(
      exec(
        target,
        target === "niri" ? ["validate", "--config", config] : ["validate", "-c", config],
      ),
    ).rejects.toThrow();
  });
}
