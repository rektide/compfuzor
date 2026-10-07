import { afterEach, expect, it } from "vitest";
import { rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fixtures } from "./fixtures.ts";
import { bindRegistryPolicies } from "../../runtime/keybindings/policy.ts";
import { assertFileGuards } from "../../files/config/capture.ts";

const roots: string[] = [];
afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});
it("binds a complete public SYSTEM pair from captured portable selectors without default fallbacks", async () => {
  const f = await fixtures();
  roots.push(f.root);
  const path = join(f.owner, "registries.json");
  const side = (role: string) => ({
    roots: [{ relative: `system/${role}` }],
    writeRoot: { relative: `system/${role}` },
  });
  const document = {
    version: 1,
    audiences: { system: { providers: side("providers"), consumers: side("consumers") } },
  };
  await writeFile(path, JSON.stringify(document));
  const bound = await bindRegistryPolicies("system", path);
  expect(bound.providers.roots).toEqual([join(f.owner, "system/providers")]);
  expect(bound.consumers.writeRoot).toBe(join(f.owner, "system/consumers"));
  await expect(bindRegistryPolicies("user", path)).rejects.toThrow("refusing default fallback");
  await writeFile(
    path,
    JSON.stringify({ version: 1, audiences: { system: { providers: side("providers") } } }),
  );
  await expect(bindRegistryPolicies("system", path)).rejects.toThrow("refusing fallback");
  await expect(assertFileGuards(bound.guards)).rejects.toThrow("source changed");
});
