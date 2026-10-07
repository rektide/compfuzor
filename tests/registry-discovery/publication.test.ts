import { afterEach, expect, it } from "vitest";
import { readFile, rm, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fixtures } from "./fixtures.ts";
import { keybindingConsumers } from "../../runtime/keybindings/registry.ts";
import { planRegistration, applyRegistration } from "../../runtime/registry/register.ts";
import { assertRegistryGuards, verifyRegistryGuard } from "../../runtime/registry/guard.ts";

const roots: string[] = [];
afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});
async function setup() {
  const f = await fixtures();
  roots.push(f.root);
  return f;
}

it("accepts absent-before and only the exact planned owner reference, including already-published idempotence", async () => {
  const f = await setup(),
    request = { domain: keybindingConsumers, policy: f.policy, source: f.consumer };
  const one = await planRegistration(request),
    two = await planRegistration(request);
  expect(await verifyRegistryGuard(one.expectation)).toBe("before");
  await applyRegistration(request, one);
  expect(await verifyRegistryGuard(two.expectation)).toBe("published");
  expect(await applyRegistration(request, two)).toMatchObject({ disposition: "current" });
  await assertRegistryGuards([one.expectation]);
});

it("rejects foreign same-ID publication and new higher control before or after own delivery", async () => {
  const f = await setup(),
    request = { domain: keybindingConsumers, policy: f.policy, source: f.consumer };
  const plan = await planRegistration(request),
    other = join(f.owner, "foreign.json");
  await writeFile(other, await readFile(f.consumer));
  await symlink(other, plan.destination);
  await expect(applyRegistration(request, plan)).rejects.toThrow("registration changed");
  await rm(plan.destination);
  const mask = join(f.overlay, "deck-main.json");
  await symlink("/dev/null", mask);
  await expect(applyRegistration(request, plan)).rejects.toThrow("registration changed");
  await rm(mask);
  await applyRegistration(request, plan);
  await symlink("/dev/null", mask);
  await expect(assertRegistryGuards([plan.expectation])).rejects.toThrow("registration changed");
});

it("rejects descriptor edits and alternate physical slots while preserving admitted ownership", async () => {
  const f = await setup(),
    request = { domain: keybindingConsumers, policy: f.policy, source: f.consumer };
  const plan = await planRegistration(request),
    original = await readFile(f.consumer);
  await writeFile(f.consumer, original.toString().replace('"niri"', '"umbriel"'));
  await expect(applyRegistration(request, plan)).rejects.toThrow("source changed");
  await writeFile(f.consumer, original);
  await symlink(f.consumer, `${plan.destination}.disabled`);
  await expect(applyRegistration(request, plan)).rejects.toThrow("registration changed");
});
