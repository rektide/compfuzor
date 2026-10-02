/**
 * Pure semantic core for independently named actions and their named bindings.
 * Callers supply decoded, ordered source layers; this module never discovers
 * files, reads environment, executes commands, registers sources or publishes
 * CONFIG outputs. Target refinements are resolved within each layer before later
 * patches, preserving producer defaults without hiding consumer overrides.
 *
 * Composition establishes references and limited chord ownership, not complete
 * native-schema validity. Serializers and the CONFIG closure validator handle
 * native material and admission before the runner's sole commit boundary.
 * @see /doc/config/keybindings.md
 */

/** Explicit compositor selection supplied by the consumer; never inferred from PATH. */
export type Target = "niri" | "umbriel";
/** Native property/argument value; decoding rejects non-finite numbers and NUL text. */
export type Scalar = string | number | boolean;
/** Named scalar native properties, merged by key rather than by generic deep merge. */
export type Properties = Record<string, Scalar>;
/** Decoded Niri action node; the native validator remains authoritative for its schema. */
export type NiriNative = {
  /** Native node name, not a shell program or the domain action ID. */
  name: string;
  /** Ordered positional values, supplied explicitly by the source record. */
  args: Scalar[];
  /** Named node properties; decoded names are safe to serialize as KDL identifiers. */
  properties: Properties;
};
/** One mutually exclusive implementation; replacement never concatenates argv or bodies. */
export type Implementation =
  | {
      /** Portable literal argv invocation, rendered as native spawn. */
      kind: "exec";
      /** Complete nonempty argv; the first item is the program, later items may be empty. */
      argv: string[];
    }
  | {
      /** Explicit trusted shell material; never executed during composition. */
      kind: "script";
      /** Shell program rendered with `-c`; no generated executable is implied. */
      shell: string;
      /** Complete script text, passed as one shell argument rather than merged. */
      body: string;
    }
  | {
      /** Implementation available only to the Niri adapter. */
      kind: "niri-native";
      /** Structured native node selected during target-layer resolution. */
      value: NiriNative;
    }
  | {
      /** Implementation available only to the Umbriel adapter. */
      kind: "umbriel-native";
      /** Complete native action spelling, including any native argument suffix. */
      value: string;
    };
/** Partial action fields for a definition, named patch or target refinement. */
export type ActionFields = {
  /** Whole implementation replacement; omission inherits an earlier layer. */
  implementation?: Implementation;
  /** False suppresses availability on this target; referenced unavailable actions fail. */
  enabled?: boolean;
};
/** Partial binding fields with field-specific replacement and extension semantics. */
export type BindingFields = {
  /** Authoritative action ID reference; patches may omit it without repeating commands. */
  action?: string;
  /** Replaces all prior chords/additions; an explicit empty list renders no chords. */
  keys?: string[];
  /** Deliberate chord union after replacement; not a rule for other arrays such as argv. */
  addKeys?: string[];
  /** Optional display title; Niri maps this to its overlay-title property. */
  title?: string;
  /** Scalar native binding options, shallowly merged by name across source layers. */
  options?: Properties;
  /** False excludes this binding from target resolution and output membership. */
  enabled?: boolean;
};
/** One decoded record with source provenance; filenames do not replace its YAML ID. */
export type Contribution = {
  /** Record-authored ID, unique within its action or binding namespace unless patched. */
  id: string;
  /** True requires an earlier same-kind ID; false claims a new definition. */
  patch: boolean;
  /** Caller-provided diagnostic/provenance label, usually a source identity and path. */
  source: string;
} & (
  | {
      /** Independent named executable/native action declaration. */
      kind: "action";
      /** Shared fields applied before this record's selected target refinement. */
      fields: ActionFields;
      /** Target-specific partial replacements, not separately registered actions. */
      targets: Partial<Record<Target, ActionFields>>;
    }
  | {
      /** Named invoker declaration referring to an independently named action. */
      kind: "keybinding";
      /** Shared fields, including suggested chords and optional patches. */
      fields: BindingFields;
      /** Selected-target replacement/addition layer applied before later source patches. */
      targets: Partial<Record<Target, BindingFields>>;
    }
);
/** Available action after ordered composition for one target, before native rendering. */
export type EffectiveAction = {
  /** Original record ID, unchanged by source path or target material naming. */
  id: string;
  /** Selected whole implementation; no fallback is fabricated for target-only actions. */
  implementation: Implementation;
  /** Ordered contributing source labels for diagnostics, not filesystem registrations. */
  sources: string[];
};
/** Binding with an available action reference and final ordered chord selection. */
export type ResolvedBinding = {
  /** Stable named binding identity used later for material and managed block names. */
  id: string;
  /** Resolved action value; several bindings may refer to this same domain action. */
  action: EffectiveAction;
  /** Deduplicated chords in source order; cross-binding identity conflicts already checked. */
  keys: string[];
  /** Effective optional title, retained independently from action implementation. */
  title?: string;
  /** Effective native scalar options; target semantic validity still needs admission. */
  options: Properties;
  /** Ordered binding source provenance, including intentional patches. */
  sources: string[];
};
/** Pure result for one target; not an artifact set, source snapshot or commit result. */
export type Composition = {
  /** Consumer-selected compositor whose refinements were applied. */
  target: Target;
  /** Available implementations; unreferenced target-only actions may be absent. */
  actions: EffectiveAction[];
  /** Enabled resolved bindings, including bindings with an explicit empty chord list. */
  bindings: ResolvedBinding[];
};

type State<F> = { fields: F; sources: string[] };

/**
 * Field-specific merge: supplying keys resets earlier addKeys, while addKeys alone
 * extends the prior selection. Actual union/deduplication happens after layering;
 * this must not become generic array concatenation for action argv.
 */
function mergeBinding(base: BindingFields, patch: BindingFields): BindingFields {
  const { addKeys, ...replacement } = patch;
  return {
    ...base,
    ...replacement,
    keys: patch.keys ?? base.keys,
    addKeys: [...(patch.keys === undefined ? (base.addKeys ?? []) : []), ...(addKeys ?? [])],
    options: { ...base.options, ...patch.options },
  };
}

/**
 * Produce the deliberately limited identity used to detect effective chord overlap.
 * Only modifier ordering/case is normalized; key spelling is retained. Configurable
 * Mod equivalence and XKB aliases remain the native validator's concern.
 * @param chord Decoded ordinary `+` chord, not arbitrary native submap syntax.
 * @returns Deterministic comparison string; performs no I/O or target discovery.
 */
export function chordIdentity(chord: string): string {
  const tokens = chord.split("+");
  const key = tokens.pop()!;
  return [...tokens.map((token) => token.toLowerCase()).sort(), key].join("+");
}

/**
 * Resolve ordered source layers into named actions and bindings for one compositor.
 * Each record's target fields apply before advancing to later producer/user layers.
 * Disabled bindings are omitted; an action with no target implementation is omitted
 * unless an enabled binding tries to reference it, which is an error.
 * @param contributions Decoded layers in explicit precedence order; no files are read.
 * @param target Consumer-selected target; only its refinements participate.
 * @returns Effective values/provenance ready for rendering, without publishing state.
 * @throws On duplicate definitions, orphan patches, unavailable references, missing
 * keys, wrong-target native implementations or conflicting effective chords.
 * @see /doc/config/keybindings.md
 */
export function compose(contributions: readonly Contribution[], target: Target): Composition {
  const actions = new Map<string, State<ActionFields>>();
  const bindings = new Map<string, State<BindingFields>>();
  for (const contribution of contributions) {
    const states = contribution.kind === "action" ? actions : bindings;
    const prior = states.get(contribution.id);
    if (contribution.patch && !prior)
      throw new Error(
        `${contribution.source}: patch has no ${contribution.kind} ${contribution.id}`,
      );
    if (!contribution.patch && prior)
      throw new Error(
        `${contribution.source}: duplicate ${contribution.kind} ${contribution.id}; use patch: true`,
      );
    const sources = [...(prior?.sources ?? []), contribution.source];
    // Resolve each layer's target refinement BEFORE user patches. A user's
    // ordinary keys patch must not be hidden by a producer's niri.keys default.
    if (contribution.kind === "action") {
      const fields = { ...contribution.fields, ...contribution.targets[target] };
      actions.set(contribution.id, {
        fields: { ...actions.get(contribution.id)?.fields, ...fields },
        sources,
      });
    } else {
      const fields = mergeBinding(contribution.fields, contribution.targets[target] ?? {});
      bindings.set(contribution.id, {
        fields: mergeBinding(bindings.get(contribution.id)?.fields ?? {}, fields),
        sources,
      });
    }
  }
  const effectiveActions: EffectiveAction[] = [];
  for (const [id, { fields, sources }] of actions) {
    if (fields.enabled === false) continue;
    // A target-only native action need not acquire a fictional portable body.
    // References on unsupported targets are rejected below.
    if (!fields.implementation) continue;
    if (
      fields.implementation.kind.endsWith("native") &&
      fields.implementation.kind !== `${target}-native`
    ) {
      throw new Error(`action ${id}: native implementation does not support ${target}`);
    }
    effectiveActions.push({ id, implementation: fields.implementation, sources });
  }
  const resolved: ResolvedBinding[] = [];
  const chords = new Map<string, string>();
  for (const [id, { fields, sources }] of bindings) {
    if (fields.enabled === false) continue;
    const action = effectiveActions.find((entry) => entry.id === fields.action);
    if (!action)
      throw new Error(
        `keybinding ${id}: unresolved action ${String(fields.action)} (${sources.join(", ")})`,
      );
    if (!fields.keys)
      throw new Error(
        `keybinding ${id}: keys are required; use keys: [] to suppress target bindings`,
      );
    const keys: string[] = [];
    const local = new Set<string>();
    for (const key of [...fields.keys, ...(fields.addKeys ?? [])]) {
      const identity = chordIdentity(key);
      if (local.has(identity)) continue; // Explicit additional keys form a union.
      local.add(identity);
      const owner = chords.get(identity);
      if (owner) throw new Error(`${target}: chord ${key} is shared by ${owner} and ${id}`);
      chords.set(identity, id);
      keys.push(key);
    }
    resolved.push({
      id,
      action,
      keys,
      title: fields.title,
      options: fields.options ?? {},
      sources,
    });
  }
  return { target, actions: effectiveActions, bindings: resolved };
}
