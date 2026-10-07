/** Owned deployment fixtures, always beneath the project's ignored scratch area. */
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { explicitPolicy } from "../../runtime/registry/policy.ts";
import type { RegistryPolicy } from "../../runtime/registry/model.ts";

export type Fixtures = {
  root: string;
  owner: string;
  lower: string;
  writable: string;
  overlay: string;
  provider: string;
  consumer: string;
  zim: string;
  resource: string;
  policy: RegistryPolicy;
};
export async function fixtures(): Promise<Fixtures> {
  const scratch = resolve(".test-agent/registry-discovery/implementation");
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(join(scratch, "case-"));
  const owner = join(root, "owners");
  const lower = join(root, "lower");
  const writable = join(root, "data");
  const overlay = join(root, "config");
  for (const dir of [owner, lower, writable, overlay]) await mkdir(dir, { recursive: true });
  const resource = join(owner, "action", "media-volume-up.yaml");
  await mkdir(join(owner, "action"));
  await writeFile(
    resource,
    "id: media-volume-up\nexec: [wpctl, set-volume, '@DEFAULT_AUDIO_SINK@', '0.03+', '-l', '1.0']\n",
  );
  const provider = join(owner, "keybinding-producer.json");
  const consumer = join(owner, "deck-main.json");
  const zim = join(owner, "zim-offer.json");
  await writeFile(
    provider,
    JSON.stringify({
      version: 1,
      producer: "media-keys-main",
      order: 20,
      resources: [{ path: resource }],
      targets: ["niri", "umbriel"],
    }),
  );
  await writeFile(
    consumer,
    JSON.stringify({
      version: 1,
      id: "deck-main",
      adapter: "niri",
      audience: "user",
      profile: { path: join(owner, "keybinding-niri.json") },
      contexts: ["user"],
      defaultContext: "user",
    }),
  );
  await writeFile(
    zim,
    JSON.stringify({
      version: 1,
      id: "shell-tools",
      fragments: [{ channel: "zimrc", name: "20-tools.conf", path: join(owner, "20-tools.conf") }],
    }),
  );
  return {
    root,
    owner,
    lower,
    writable,
    overlay,
    provider,
    consumer,
    zim,
    resource,
    policy: explicitPolicy("user", [lower, writable, overlay], writable),
  };
}
