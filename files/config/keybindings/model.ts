/** Pure named-action and named-binding composition; no runtime registration. */

export type Target = "niri" | "umbriel";
export type Scalar = string | number | boolean;
export type Properties = Record<string, Scalar>;
export type NiriNative = { name: string; args: Scalar[]; properties: Properties };
export type Implementation =
  | { kind: "exec"; argv: string[] }
  | { kind: "script"; shell: string; body: string }
  | { kind: "niri-native"; value: NiriNative }
  | { kind: "umbriel-native"; value: string };
export type ActionFields = { implementation?: Implementation; enabled?: boolean };
export type BindingFields = {
  action?: string;
  keys?: string[];
  addKeys?: string[];
  title?: string;
  options?: Properties;
  enabled?: boolean;
};
export type Contribution = {
  id: string;
  patch: boolean;
  source: string;
} & (
  | { kind: "action"; fields: ActionFields; targets: Partial<Record<Target, ActionFields>> }
  | { kind: "keybinding"; fields: BindingFields; targets: Partial<Record<Target, BindingFields>> }
);
export type EffectiveAction = { id: string; implementation: Implementation; sources: string[] };
export type ResolvedBinding = {
  id: string;
  action: EffectiveAction;
  keys: string[];
  title?: string;
  options: Properties;
  sources: string[];
};
export type Composition = {
  target: Target;
  actions: EffectiveAction[];
  bindings: ResolvedBinding[];
};

type State<F> = { fields: F; sources: string[] };

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

/** Only modifier ordering/case is normalized, not target-dependent Mod resolution
 * or XKB key aliases. Native whole-root validation remains necessary. */
export function chordIdentity(chord: string): string {
  const tokens = chord.split("+");
  const key = tokens.pop()!;
  return [...tokens.map((token) => token.toLowerCase()).sort(), key].join("+");
}

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
