/** Closed producer membership, context binding and generated installation. */
import { join, normalize, isAbsolute } from "node:path";
import { captureFile, fileText, type FileGuard } from "../capture.ts";
import { resolvePathSelector, type PathSelector } from "../context.ts";
import { withInputBatch, type InputRegistration } from "../registration.ts";
import { decodeYaml } from "./decode.ts";
import {
  assembleConsumer,
  type ConsumerOptions,
  type ConsumerRequest,
  type ConsumerResult,
  type YamlSelection,
} from "./consumer.ts";
import type { NativeSource } from "./materials.ts";
import type { Target } from "./model.ts";

export type PlacementStrategy = "direct" | "copy" | "link";
export type Profile = {
  version: 1;
  target: Target;
  contexts: Record<string, { scope: "user" | "system"; root: PathSelector; subpath?: string }>;
  rootFile?: PathSelector;
  materialRoot?: PathSelector;
  membership?: PathSelector;
  placement?: PlacementStrategy;
  placementDirectory?: PathSelector;
  registration?: "copy" | "link";
  baseline?: PathSelector[];
  personal?: PathSelector[];
  userSources?: { path: PathSelector; whenPresent?: boolean; disabledSuffix?: string }[];
  nativeSources?: (Omit<NativeSource, "path" | "placement"> & {
    path: PathSelector;
    placement: { strategy: "direct" } | { strategy: "copy" | "link"; path: PathSelector };
  })[];
  bindings?: Record<
    string,
    {
      order?: number;
      incorporation?: "include" | "inline";
      placement?: { strategy: "direct" } | { strategy: "copy" | "link"; path: PathSelector };
    }
  >;
  templateFile?: PathSelector;
};
export type ProducerManifest = {
  version: 1;
  producer: string;
  order: number;
  resources: { path: string }[];
  targets: Target[];
};
type Resource = { path: string; kind: "action" | "keybinding"; id: string };
export type Membership = {
  version: 1;
  target: Target;
  groups: Record<string, { enabled: boolean; order: number; resources: Resource[] }>;
};
export type HostOptions = Omit<ConsumerOptions, "request"> & {
  profile: Profile;
  profileGuard?: FileGuard;
  context: string;
  scope: "user" | "system";
  mode?: "assemble" | "seed" | "refresh";
};
const ID = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;

export function defaultProfile(target: Target): Profile {
  return {
    version: 1,
    target,
    contexts: { user: { scope: "user", root: { path: "${XDG_CONFIG_HOME}" }, subpath: target } },
    placement: "link",
    registration: "link",
    baseline: target === "umbriel" ? [{ path: "/usr/local/share/umbriel/config.toml" }] : [],
  };
}

function bindProfile(options: HostOptions): {
  base: string;
  statePath: string;
  request: ConsumerRequest;
} {
  const profile = options.profile;
  if (profile.version !== 1 || (profile.target !== "niri" && profile.target !== "umbriel"))
    throw new Error("unsupported keybinding profile");
  const context = profile.contexts[options.context];
  if (!context || context.scope !== options.scope)
    throw new Error(`context ${options.context} does not match generated ${options.scope} scope`);
  const root = resolvePathSelector(
    context.root,
    undefined,
    `keybinding context ${options.context}.root`,
  );
  const base = context.subpath
    ? resolvePathSelector({ relative: context.subpath }, root, "keybinding context subpath")
    : root;
  const path = (selector: PathSelector, label: string) =>
    resolvePathSelector(selector, base, label);
  const statePath = path(
    profile.membership ?? { relative: ".keybindings/membership.json" },
    "membership",
  );
  const nativeSources: NativeSource[] = (profile.nativeSources ?? []).map((source) => ({
    ...source,
    path: path(source.path, `native ${source.id}`),
    placement:
      source.placement.strategy === "direct"
        ? { strategy: "direct" }
        : {
            strategy: source.placement.strategy,
            path: path(source.placement.path, `native ${source.id} placement`),
          },
  }));
  const bindings: NonNullable<ConsumerRequest["bindings"]> = {};
  for (const [id, value] of Object.entries(profile.bindings ?? {}))
    bindings[id] = {
      ...value,
      placement:
        value.placement === undefined
          ? undefined
          : value.placement.strategy === "direct"
            ? { strategy: "direct" }
            : {
                strategy: value.placement.strategy,
                path: path(value.placement.path, `binding ${id} placement`),
              },
    };
  return {
    base,
    statePath,
    request: {
      version: 1,
      target: profile.target,
      root: {
        path: path(
          profile.rootFile ?? {
            relative: profile.target === "niri" ? "config.kdl" : "config.toml",
          },
          "consumer root",
        ),
        ...(profile.templateFile
          ? { templateFile: path(profile.templateFile, "root template") }
          : {}),
      },
      materialRoot: path(
        profile.materialRoot ?? { relative: ".keybindings/generated" },
        "material root",
      ),
      nativeSources,
      bindings,
      baseline: (profile.baseline ?? []).map((selector) => path(selector, "baseline")),
      personal: (profile.personal ?? []).map((selector) => path(selector, "personal")),
      mode: options.mode ?? "assemble",
    },
  };
}

async function readState(
  path: string,
  target: Target,
): Promise<{ state: Membership; guard: FileGuard }> {
  const file = await captureFile(path);
  const text = fileText(file);
  const state =
    text === undefined
      ? { version: 1 as const, target, groups: {} }
      : (JSON.parse(text) as Membership);
  if (
    state.version !== 1 ||
    state.target !== target ||
    !state.groups ||
    typeof state.groups !== "object" ||
    Array.isArray(state.groups)
  )
    throw new Error("invalid keybinding membership");
  for (const [id, group] of Object.entries(state.groups)) {
    if (
      !ID.test(id) ||
      typeof group.enabled !== "boolean" ||
      !Number.isFinite(group.order) ||
      !Array.isArray(group.resources)
    )
      throw new Error(`invalid membership group ${id}`);
    for (const resource of group.resources)
      if (
        !isAbsolute(resource.path) ||
        !ID.test(resource.id) ||
        (resource.kind !== "action" && resource.kind !== "keybinding")
      )
        throw new Error(`invalid declared resource in ${id}`);
  }
  return { state, guard: file.guard };
}

/** User overlays with explicit whenPresent stay dormant when a producer is
 * disabled/absent. Core composition remains strict for unconditional patches. */
async function selectedRequest(
  bound: ReturnType<typeof bindProfile>,
  state: Membership,
  options: HostOptions,
): Promise<{ request: ConsumerRequest; guards: FileGuard[] }> {
  const request = bound.request;
  const selected: YamlSelection[] = [];
  const guards: FileGuard[] = [];
  const identities = new Set<string>();
  const groups = Object.entries(state.groups)
    .filter(([, group]) => group.enabled)
    .sort(([a, first], [b, second]) => first.order - second.order || (a < b ? -1 : a > b ? 1 : 0));
  const placement = options.profile.placement ?? "link";
  if (!["direct", "copy", "link"].includes(placement))
    throw new Error("invalid native placement policy");
  const directory = resolvePathSelector(
    options.profile.placementDirectory ?? { relative: "keybindings" },
    bound.base,
    "placement directory",
  );
  let order = 0;
  const read = async (path: string, suffix?: string) => {
    const active = await captureFile(path);
    guards.push(active.guard);
    if (suffix) {
      if (!/^\.[A-Za-z0-9_.-]+$/.test(suffix)) throw new Error("invalid source disabled suffix");
      const disabled = await captureFile(path + suffix);
      guards.push(disabled.guard);
      if (disabled.guard.kind !== "missing" && active.guard.kind !== "missing")
        throw new Error(`both enabled and disabled slots exist: ${path}`);
      if (disabled.guard.kind !== "missing") return undefined;
    }
    const text = fileText(active);
    if (text === undefined) throw new Error(`missing declared membership source ${path}`);
    return decodeYaml(text, path);
  };
  for (const [, group] of groups)
    for (const resource of group.resources) {
      const record = await read(resource.path, ".disabled");
      if (!record) continue;
      if (record.kind !== resource.kind || record.id !== resource.id)
        throw new Error(
          `record identity changed; reinstall declared contribution: ${resource.path}`,
        );
      selected.push({ path: resource.path, disabledSuffix: ".disabled" });
      identities.add(`${record.kind}/${record.id}`);
      if (record.kind === "keybinding" && !record.patch) {
        request.bindings![record.id] = {
          order: order++,
          placement:
            placement === "direct"
              ? { strategy: "direct" }
              : {
                  strategy: placement,
                  path: join(
                    directory,
                    `${record.id}.binding.${request.target === "niri" ? "kdl" : "toml"}`,
                  ),
                },
          ...request.bindings![record.id],
        };
      }
    }
  for (const source of options.profile.userSources ?? []) {
    const path = resolvePathSelector(source.path, bound.base, "user overlay");
    const record = await read(path, source.disabledSuffix);
    if (!record) continue;
    if (record.patch && source.whenPresent && !identities.has(`${record.kind}/${record.id}`))
      continue;
    selected.push({ path, disabledSuffix: source.disabledSuffix });
    identities.add(`${record.kind}/${record.id}`);
  }
  request.yamlSources = selected;
  return { request, guards };
}

async function applyState(
  bound: ReturnType<typeof bindProfile>,
  state: Membership,
  guard: FileGuard,
  options: HostOptions,
  changed: boolean,
): Promise<ConsumerResult> {
  const selected = await selectedRequest(bound, state, options);
  selected.request.mode = options.mode ?? "assemble";
  return assembleConsumer({
    ...options,
    request: selected.request,
    inputGuards: [
      guard,
      ...selected.guards,
      ...(options.profileGuard ? [options.profileGuard] : []),
    ],
    supplementalOutputs: changed
      ? [{ path: bound.statePath, text: JSON.stringify(state, null, 2) + "\n" }]
      : [],
  });
}

export async function assembleHost(options: HostOptions): Promise<ConsumerResult> {
  const bound = bindProfile(options);
  const { state, guard } = await readState(bound.statePath, options.profile.target);
  return applyState(bound, state, guard, options, false);
}

export async function installProducer(
  manifest: ProducerManifest,
  options: HostOptions,
): Promise<ConsumerResult> {
  if (
    manifest.version !== 1 ||
    !ID.test(manifest.producer) ||
    !Number.isFinite(manifest.order) ||
    !Array.isArray(manifest.resources) ||
    !manifest.targets.includes(options.profile.target)
  )
    throw new Error("invalid producer manifest/target");
  if (options.check)
    throw new Error("producer registration is explicit mutation; check host assembly instead");
  const bound = bindProfile(options);
  const { state, guard } = await readState(bound.statePath, options.profile.target);
  const resources: Resource[] = [];
  const registrations: InputRegistration[] = [];
  const seen = new Set<string>();
  for (const source of manifest.resources) {
    const file = await captureFile(source.path);
    const text = fileText(file);
    if (text === undefined) throw new Error(`missing packaged producer source ${source.path}`);
    const record = decodeYaml(text, source.path);
    const identity = `${record.kind}/${record.id}`;
    if (seen.has(identity)) throw new Error(`duplicate packaged resource ${identity}`);
    seen.add(identity);
    const path = join(
      bound.base,
      ".keybindings/source",
      manifest.producer,
      record.kind === "action" ? "action" : "keybinding",
      `${record.id}.yaml`,
    );
    resources.push({ path, kind: record.kind, id: record.id });
    registrations.push({
      source: normalize(source.path),
      destination: path,
      strategy: options.profile.registration ?? "link",
      disabledSuffix: ".disabled",
    });
  }
  state.groups[manifest.producer] = {
    enabled: state.groups[manifest.producer]?.enabled ?? true,
    order: manifest.order,
    resources,
  };
  return withInputBatch(
    registrations,
    () => applyState(bound, state, guard, { ...options, mode: options.mode ?? "seed" }, true),
    { success: (result) => result.code === 0, workspaceRoot: options.workspaceRoot },
  );
}

export async function toggleGroup(
  group: string,
  enabled: boolean,
  options: HostOptions,
): Promise<ConsumerResult> {
  const bound = bindProfile(options);
  const { state, guard } = await readState(bound.statePath, options.profile.target);
  if (!Object.hasOwn(state.groups, group)) throw new Error(`unknown contribution ${group}`);
  state.groups[group].enabled = enabled;
  return applyState(bound, state, guard, options, true);
}

export async function loadProfile(
  path: string,
): Promise<{ profile: Profile; profileGuard: FileGuard }> {
  const file = await captureFile(path);
  const text = fileText(file);
  if (text === undefined) throw new Error(`missing keybinding consumer profile ${path}`);
  return { profile: JSON.parse(text) as Profile, profileGuard: file.guard };
}
