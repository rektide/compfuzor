/**
 * Durable, CLOSED producer membership and invocation-time binding of consumer
 * profiles. The controller packages selectors/manifests; this adapter reads those
 * declarations and registered YAML, orders producer groups before consumer layers,
 * and delegates native work to assembleConsumer. No directory/PATH scan adds members.
 *
 * Producer installation refreshes managed YAML registrations as one batch; native
 * editable placements independently seed/preserve unless refresh is requested.
 * Membership updates are supplemental CONFIG candidates, accepted only with the
 * outputs/root in the existing runner's commit, not an earlier metadata write.
 * Registration rollback covers normal failures, not crash atomicity or reader isolation.
 * @see /doc/config/keybinding-producers.md
 * @see /design/keybindings/implementation2.gpt61sol.md
 * @see /design/keybindings/review-fixes0.gpt61sol.md
 */
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

/** Native material placement, not managed source-YAML registration strategy. */
export type PlacementStrategy = "direct" | "copy" | "link";
/** Render-time host policy whose portable paths resolve against the selected context at invocation. */
export type Profile = {
  /** Profile format version; loader does not migrate unsupported versions implicitly. */
  version: 1;
  /** Declared target; install CLI and membership state must agree with it. */
  target: Target;
  /** Explicit named CONFIG-style contexts, not a universal deployment registry. */
  contexts: Record<
    string,
    {
      /** Expected installer scope; runtime rejects context/scope mismatch before delivery. */
      scope: "user" | "system";
      /** HOME/XDG/system/env selector resolved with the existing CONFIG path helper. */
      root: PathSelector;
      /** Optional contained relative suffix forming the base for profile-relative paths. */
      subpath?: string;
    }
  >;
  /** Root output selector; default is config.kdl/config.toml under the bound base. */
  rootFile?: PathSelector;
  /** Generated definitions/companions selector; default .keybindings/generated. */
  materialRoot?: PathSelector;
  /** Durable closed state selector; default .keybindings/membership.json. */
  membership?: PathSelector;
  /** Default native receiver policy, link by default; not source registration copy/link. */
  placement?: PlacementStrategy;
  /** Default receiver directory selector, keybindings/ under the selected base. */
  placementDirectory?: PathSelector;
  /** Managed YAML copy/link policy; producer reinstall refreshes these declarations. */
  registration?: "copy" | "link";
  /** Leading bootstrap references; existing root baseline text is not rewritten. */
  baseline?: PathSelector[];
  /** Late bootstrap references; existing personal text remains author-owned. */
  personal?: PathSelector[];
  /** Ordered consumer-owned YAML layers after enabled producer groups. */
  userSources?: {
    /** Portable source selector resolved at invocation, not a filename-derived record ID. */
    path: PathSelector;
    /** A patch is dormant until its same-kind/ID base exists; unconditional patches stay strict. */
    whenPresent?: boolean;
    /** Explicit alternate disabled slot convention; both slots existing is invalid. */
    disabledSuffix?: string;
  }[];
  /** Authored native memberships sharing generated-body selection semantics after path binding. */
  nativeSources?: (Omit<NativeSource, "path" | "placement"> & {
    /** Portable donor/native input selector, resolved before consumer capture. */
    path: PathSelector;
    /** Receiver policy with portable rather than already concrete paths. */
    placement:
      | {
          /** Use the source directly, without receiver delivery. */
          strategy: "direct";
        }
      | {
          /** Native copy/link selection; seed/preserve versus refresh is invocation policy. */
          strategy: "copy" | "link";
          /** Receiver selector resolved against the chosen context base. */
          path: PathSelector;
        };
  })[];
  /** Policies by binding ID, not membership declarations; inactive settings may remain. */
  bindings?: Record<
    string,
    {
      /** Optional contribution ordering override after membership-derived defaults. */
      order?: number;
      /** Native root representation; inline is initially Niri-only. */
      incorporation?: "include" | "inline";
      /** Binding-specific receiver override, resolved at invocation. */
      placement?:
        | {
            /** Include the generated canonical definition directly. */
            strategy: "direct";
          }
        | {
            /** Choose an editable copy or source-tracking link receiver. */
            strategy: "copy" | "link";
            /** Receiver selector, not the producer's packaged system path. */
            path: PathSelector;
          };
    }
  >;
  /** Explicit missing-root template selector; never an implicit overwrite policy for existing text. */
  templateFile?: PathSelector;
};
/** Controller-packaged producer declaration; an empty resource list remains a real producer update. */
export type ProducerManifest = {
  /** Producer format discriminator checked before registration. */
  version: 1;
  /** Stable membership/storage group ID; does not prefix/rewrite YAML action or binding IDs. */
  producer: string;
  /** Finite group precedence; equal values sort by producer ID. */
  order: number;
  /** Exact packaged resources; reinstall replaces this list, including with [], without pruning files. */
  resources: {
    /** Concrete packaged system file; kind and authoritative ID are decoded from its YAML. */
    path: string;
  }[];
  /** Explicit generated target participation; no compositor availability scan occurs. */
  targets: Target[];
};
/** Stored record identity is a consistency assertion, never a replacement for current YAML identity. */
type Resource = {
  /** Concrete registered ACTIVE slot; disabled convention is applied at source selection. */
  path: string;
  /** Stored decoded record kind, asserted against current YAML on every assembly. */
  kind: "action" | "keybinding";
  /** Stored decoded ID, asserted rather than used to override a changed YAML identity. */
  id: string;
};
/** Durable exact source selection; pending updates publish only with CONFIG artifact commit. */
export type Membership = {
  /** State schema discriminator; not an implicit migration marker. */
  version: 1;
  /** Target of this context's state; prevents loading another compositor's graph. */
  target: Target;
  /** Explicit producer groups; stale physical files outside these lists are not rediscovered. */
  groups: Record<
    string,
    {
      /** Whole-group selection, preserved across reinstall; disabling does not delete resources. */
      enabled: boolean;
      /** Finite precedence before the group-ID tie breaker and later consumer overlays. */
      order: number;
      /** Exact registered active paths/kinds/IDs; .disabled alternate slots are interpreted on read. */
      resources: Resource[];
    }
  >;
};
/** Host invocation services plus context choice; derives a concrete ConsumerRequest upstream of capture. */
export type HostOptions = Omit<ConsumerOptions, "request"> & {
  /** Loaded/generated portable policy, bound for this invocation rather than render-time HOME. */
  profile: Profile;
  /** Optional observation of profile file state, included in the pre-commit closure guard set. */
  profileGuard?: FileGuard;
  /** Explicit context key in profile.contexts, commonly user. */
  context: string;
  /** Generated/caller-declared scope which must agree with the selected context. */
  scope: "user" | "system";
  /** Native placement mode; producer install defaults seed, host API defaults assemble. */
  mode?: "assemble" | "seed" | "refresh";
};
const ID = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;

/**
 * Return known user defaults without reading configuration or discovering targets.
 * The context uses invocation-time XDG resolution; native placement and managed
 * registration default to link. Umbriel references its explicit system baseline;
 * Niri deliberately fabricates no baseline. Existing roots still require adoption.
 * @param target Declared target whose default root/validator convention is desired.
 * @returns A fresh portable profile; does not provision prerequisites or create roots.
 */
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

/** Serializable invocation-bound paths; admission does not mutate membership or outputs. */
export type BoundProfile = {
  base: string;
  statePath: string;
  request: ConsumerRequest;
};

/** Resolve selectors once against an explicitly scope-checked CONFIG-style context. */
export function bindProfile(options: HostOptions): BoundProfile {
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

/** Read only declared JSON state (or an empty missing state), never infer members from directories. */
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

/**
 * Select enabled groups by order/ID, then late consumer layers, retaining input guards.
 * whenPresent makes only conditional patches dormant when their base is missing;
 * it does not weaken strict core composition or turn policy settings into members.
 * Stored resource IDs/kinds assert current YAML identity; mismatch requires reinstall.
 */
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

/** Offer changed membership as a supplemental CONFIG output, not a prior accepted metadata write. */
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

/**
 * Bind the host profile and reassemble only its closed durable membership/user layer.
 * Reads state/registered sources and delegates preparation/publication to the consumer;
 * it does not refresh source registrations, add discovered files or rewrite membership.
 * @param options Context/scope, workers and native placement mode (assemble by default).
 * @returns Consumer/runner outcome; check mode reports drift without delivery.
 * @throws On invalid profile/state/identity, absent declared inputs or consumer preparation.
 */
export async function assembleHost(
  options: HostOptions,
  admitted?: BoundProfile,
): Promise<ConsumerResult> {
  const bound = admitted ?? bindProfile(options);
  const { state, guard } = await readState(bound.statePath, options.profile.target);
  return applyState(bound, state, guard, options, false);
}

/**
 * Upsert one declared producer group and perform one coherent registration/assembly.
 * Decode authoritative YAML IDs, refresh managed source copies/links while preserving
 * disabled slots, then stage exact membership with all native outputs in CONFIG.
 * Empty resources replace the group's selection with []; stale physical files stay
 * excluded, not pruned. Group enabled state survives reinstall. Native copies default
 * to seed/preserve, independently from refreshed YAML registrations.
 * @param manifest Packaged producer identity/order/resources and explicit target list.
 * @param options Bound host policy/context and workers; check is not a registration mode.
 * @returns Consumer code/streams; only zero accepts registration and membership together
 * under normal operation. Nonzero causes the registration batch to restore old entries.
 * @throws On manifest/target/check errors, malformed or duplicate records, preflight,
 * registration or thrown preparation failures. No crash-atomicity/concurrent isolation
 * or safe retry after unknown post-publication cleanup failure is promised.
 * @see /doc/config/keybinding-producers.md
 * @see /design/keybindings/review-fixes0.gpt61sol.md
 */
export async function installProducer(
  manifest: ProducerManifest,
  options: HostOptions,
  admitted?: BoundProfile,
): Promise<ConsumerResult> {
  validateProducerManifest(manifest, options.profile.target);
  if (options.check)
    throw new Error("producer registration is explicit mutation; check host assembly instead");
  const bound = admitted ?? bindProfile(options);
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

/** Shared structural admission; producer source decoding remains inside its complete operation. */
export function validateProducerManifest(manifest: ProducerManifest, target: Target): void {
  if (
    manifest.version !== 1 ||
    !ID.test(manifest.producer) ||
    !Number.isFinite(manifest.order) ||
    !Array.isArray(manifest.resources) ||
    !Array.isArray(manifest.targets) ||
    !manifest.targets.includes(target)
  )
    throw new Error("invalid producer manifest/target");
}

/**
 * Stage a named group's enabled flag with native reassembly at the same CONFIG commit.
 * Resource files/slots remain untouched; reinstall retains this explicit state and
 * whenPresent user patches can become dormant without reactivating the group.
 * @param group Existing membership producer ID, not an action/binding ID.
 * @param enabled Whether this group enters the next closed selection.
 * @param options Explicit host context and assembly services.
 * @returns Consumer outcome; a failed commit does not accept the new membership flag.
 * @throws On unknown groups, invalid profile/state or consumer preparation errors.
 */
export async function toggleGroup(
  group: string,
  enabled: boolean,
  options: HostOptions,
  admitted?: BoundProfile,
): Promise<ConsumerResult> {
  const bound = admitted ?? bindProfile(options);
  const { state, guard } = await readState(bound.statePath, options.profile.target);
  if (!Object.hasOwn(state.groups, group)) throw new Error(`unknown contribution ${group}`);
  state.groups[group].enabled = enabled;
  return applyState(bound, state, guard, options, true);
}

/**
 * Read/decode profile JSON and retain an observed-state guard for later validation.
 * This only checks usable captured text/JSON; binding validates profile/context
 * shape later. No selector resolution, registration, root write or commit occurs.
 * @param path Explicit profile file selected by the caller/portable locator boundary.
 * @returns Parsed profile and its file/link/physical-parent/content observation.
 * @throws On missing/dangling/non-file input, invalid UTF-8/JSON or capture failure.
 */
export async function loadProfile(path: string): Promise<{
  /** Captured policy, with portable selectors still unresolved until context binding. */
  profile: Profile;
  /** Captured profile observation included in later native admission guards. */
  profileGuard: FileGuard;
}> {
  const file = await captureFile(path);
  const text = fileText(file);
  if (text === undefined) throw new Error(`missing keybinding consumer profile ${path}`);
  return { profile: JSON.parse(text) as Profile, profileGuard: file.guard };
}
