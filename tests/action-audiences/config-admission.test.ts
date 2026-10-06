import { afterEach, expect, test, vi } from "vitest";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { parseConfigCommandArgs } from "../../files/config/cli.ts";
import { admitConfigCommand, runAdmittedConfigCommand } from "../../files/config/runtime.ts";
import type { ConfigSpec } from "../../files/config/context.ts";

const roots: string[] = [];
afterEach(async () => {
  vi.unstubAllEnvs();
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

async function fixture() {
  const scratch = resolve(".test-agent/action-audiences");
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(join(scratch, "config-admission-"));
  roots.push(root);
  const source = join(root, "donor.txt");
  await writeFile(source, "canonical output\n");
  const binding = { output: { relative: "receiver.txt" }, inputs: [] };
  const spec: ConfigSpec = {
    version: 2,
    defaultContext: "desktop",
    installOwner: "config",
    configs: { receiver: { output: source, inputs: [], apply: true } },
    contexts: {
      desktop: {
        scope: "user",
        root: { path: join(root, "desktop") },
        configs: { receiver: binding },
      },
      laptop: {
        scope: "user",
        root: { path: join(root, "laptop") },
        configs: { receiver: binding },
      },
      host: { scope: "system", root: { path: join(root, "host") }, configs: { receiver: binding } },
      canonical: {
        scope: "system",
        canonical: true,
        root: { path: "/" },
        configs: { receiver: { output: { path: source }, inputs: [] } },
      },
    },
  };
  const path = join(root, "spec.json");
  await writeFile(path, JSON.stringify(spec));
  const options = (argv: string[] = []) =>
    parseConfigCommandArgs(
      ["--spec", path, "--action", "publish", "--strategy", "copy", ...argv],
      root,
      "command.ts",
    );
  return { root, spec, path, options };
}

test("bound CONFIG admission rejects effective context, environment, action and spec audience escapes before effects", async () => {
  const { options, path, spec } = await fixture();
  const declared = { action: "publish", audience: "user", context: "desktop" } as const;
  expect((await admitConfigCommand(options(), declared)).contextName).toBe("desktop");
  expect((await admitConfigCommand(options(["--context", "laptop"]), declared)).contextName).toBe(
    "laptop",
  );
  await expect(admitConfigCommand(options(["--context", "host"]), declared)).rejects.toThrow(
    "not selected user audience",
  );
  vi.stubEnv("COMPFUZOR_CONFIG_CONTEXT", "host");
  await expect(admitConfigCommand(options(), declared)).rejects.toThrow(
    "not selected user audience",
  );
  vi.stubEnv("COMPFUZOR_CONFIG_CONTEXT", "laptop");
  expect((await admitConfigCommand(options(), declared)).contextName).toBe("laptop");
  vi.unstubAllEnvs();
  await expect(admitConfigCommand(options(["--action", "assemble"]), declared)).rejects.toThrow(
    "does not match declared",
  );
  spec.contexts!.desktop.scope = "system";
  await writeFile(path, JSON.stringify(spec));
  await expect(admitConfigCommand(options(), declared)).rejects.toThrow(
    "not selected user audience",
  );
});

test("canonical donors and a different install owner cannot become receiver installation plans", async () => {
  const { options, spec, path } = await fixture();
  await expect(
    admitConfigCommand(options(["--context", "canonical"]), {
      action: "publish",
      audience: "system",
      context: "canonical",
    }),
  ).rejects.toThrow("canonical donor");
  spec.installOwner = "zim";
  await writeFile(path, JSON.stringify(spec));
  await expect(
    admitConfigCommand(options(["--action", "install"]), {
      action: "install",
      audience: "user",
      context: "desktop",
    }),
  ).rejects.toThrow("owned by zim");
});

test("admitted execution reuses its loaded spec and selected context rather than re-reading changed selection", async () => {
  const { options, root, path } = await fixture();
  const admitted = await admitConfigCommand(options(), {
    action: "publish",
    audience: "user",
    context: "desktop",
  });
  await writeFile(path, "changed invalid spec");
  vi.stubEnv("COMPFUZOR_CONFIG_CONTEXT", "host");
  expect(await runAdmittedConfigCommand(admitted)).toBe(0);
  expect(await readFile(join(root, "desktop/receiver.txt"), "utf8")).toBe("canonical output\n");
  await expect(readFile(join(root, "host/receiver.txt"))).rejects.toMatchObject({ code: "ENOENT" });
});
