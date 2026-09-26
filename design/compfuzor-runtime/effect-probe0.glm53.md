---
type: ArchitectureExperiment
title: CFR→Effect probe — yieldable operation descriptors through one Effect executor
description: Scratch experiment testing schema-backed op descriptors as directly yieldable Effectable.Class values, executed via Context.Service/Layer, with additive data contributions and truthful static inspection; evidence for the parent's Effect architecture draft.
resource: /design/compfuzor-runtime/effect-probe0.glm53.md
tags: [compfuzor, runtime, effect, effectable, inspection, architecture, experiment]
status: draft
generated: { by: 'model:glm53 (GLM 5.3 max via ZAI Coding Plan)', at: 2026-09-26 }
verified: { by: unverified }
sources:
  - id: effect-checkout
    resource: ~/a/Effect-TS/effect
    title: Effect v4 checkout at git 64093976e9f595f0f9638aad5526738c78a3fa08 (2026-09-26), packages/effect 4.0.0-rc.117
  - id: probe-mandate
    resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Four-probe sequence, its retained evidence, and the comparison ask (explicit planning vs effect-based interpreters)
  - id: prior-probe
    resource: /design/compfuzor-runtime/experiment4.sxh.md
    title: Registration/dispatch probe whose seams this experiment re-tests on Effect
  - id: prior-scan
    resource: /design/compfuzor-runtime/effect-material0.glm53.md
    title: Source scan with flagged overclaims; corrected where tested below
  - id: prototype
    resource: /.test-agent/cfr-effect/experiment0/README.md
    title: Throwaway prototype, one-command demo, 24 executable checks
---

# CFR→Effect probe: descriptors that yield, one executor, honest inspection

## Question and answer

**Question.** Can a schema-backed/descriptive operation value be directly
yieldable via `Effectable.Class` while execution is entirely Effect through a
supplied `Context` service/Layer, supporting independent additive
contributions and truthful inspection — WITHOUT inventing a second executor?

**Answer (tested): yes.** An op descriptor class extends
`Effectable.Class<A, OpError, MaterialRuntime>`, carries immutable
`id/kind/concern/tags/material` fields, and its `asEffect()` is one line:
read the interpreter service and hand it `this`. Execution never happens in
the descriptor; metadata inspection never touches services; contributions are
arrays of op data collected explicitly by the consumer; typed denials and
postcondition failures are `Schema.TaggedError`s distinct from defects. The
sharp edge is exactly where predicted: **static inspection cannot see through
`Effect.gen` continuations, and any "dry walk" that tries both executes
author code and fabricates its answers** — the second executor this probe
deliberately refuses to build.

Everything below marked *tested* ran via
`node .test-agent/cfr-effect/experiment0/demo.ts` (24 checks, all passing)
and typechecked under the repo's vanilla
`tsgo --strict` (`@typescript/native-preview` 7.0.0-dev.20260707.2). Full
capture: [`scratch-demo-output.txt`](/.test-agent/cfr-effect/experiment0/scratch-demo-output.txt).

## Observed exact APIs (v4, against the pinned checkout)

Effect checkout `~/a/Effect-TS/effect` @ `64093976e9f595f0f9638aad5526738c78a3fa08`,
`packages/effect` manifest version `4.0.0-rc.117`. The published package maps
its `"."` export to `./src/index.ts` — TypeScript source is the shipped entry,
so Node 26 runs it under type-stripping with **no install at all**
(`deps.ts` imports the checkout by absolute path; no `internal/*` import from
our code).

**1. Yieldable descriptor — `Effectable.Class`**
([`Effectable.ts:70-72`](~/a/Effect-TS/effect/packages/effect/src/Effectable.ts#L70-L72)):

```ts
export abstract class Class<A, E = never, R = never> extends Base<A, E, R> {
  abstract asEffect(): Effect.Effect<A, E, R>
}
```

Our base class (from
[`kernel/ops.ts`](/.test-agent/cfr-effect/experiment0/kernel/ops.ts)):

```ts
export abstract class Op<A> extends Effectable.Class<A, OpError, MaterialRuntime> {
  abstract readonly kind: OpKind           // "inspect" | "write-file" | "link-file"
  abstract readonly id: string
  abstract readonly concern: OpConcern     // "observe" | "realize" | "publish"
  abstract readonly tags: ReadonlyArray<string>
  abstract readonly material: MaterialRef  // { root, path }
  asEffect(): Effect.Effect<A, OpError, MaterialRuntime> {
    return MaterialRuntime.use((runtime) => runtime.run(this))
  }
}
```

`yield* new WriteFile({...})` inside `Effect.gen` works exactly like a stock
Effect; `describeStatic(op)` reads the same object as plain data. *Tested*
(S1–S3).

**2. Class-style service keys — `Context.Service`**
([`Context.ts:98-128`](~/a/Effect-TS/effect/packages/effect/src/Context.ts#L98-L128)):

```ts
export class MaterialRuntime extends Context.Service<MaterialRuntime, {
  readonly run: <A>(op: Op<A>) => Effect.Effect<A, OpError>
}>()("MaterialRuntime") {}
```

**Gotcha we hit and corrected:** the `R` requirement for class-style keys is
**the class instance type** (`MaterialRuntime`), not the string literal
`"MaterialRuntime"` — `ServiceClass<Self, …> extends Service<Self, Shape>`,
so the key's identifier type is `Self`. tsgo rejected our first
`"MaterialRuntime"`-literal annotations; the string is only the runtime slot
key. The function-style `Context.Service<Shape>("Key")` defaults
`Identifier = Shape`, which is worse for tracking; class-style is the sound
pattern. Service keys are themselves yieldable (`yield* Policy` inside the
layer builder — *tested*), and `use` is
`use<A, E, R>(f: (service: Shape) => Effect<A, E, R>): Effect<A, E, R | Identifier>`
([`Context.ts:101`](~/a/Effect-TS/effect/packages/effect/src/Context.ts#L101)).

**3. One executor behind a Layer — `Layer.succeed` / `Layer.effect` /
`Layer.provide`** (Layer.ts:805/1012/1429):

```ts
export const makeMaterialRuntimeLayer = (env, policyLayer = PolicyLive) =>
  Layer.effect(MaterialRuntime, Effect.gen(function*() {
    counters.layerAcquisitions++
    const policy = yield* Policy            // service key yielded directly
    return { run: (op) => interpret(policy, env, op) }   // the ONLY executor
  })).pipe(Layer.provide(policyLayer))
```

*Tested:* a program yielding N ops acquires the layer exactly **once** (S2: 3
ops → 1 acquisition; S3: 6 ops across nested groups → 1); two separate
`Effect.runPromise` runs acquire **twice** (S6) — Layer MemoMap memoizes
construction per build, never execution. This is experiment-2's
construction-vs-occurrence distinction, native.

**4. Typed errors are data and yieldable — `Schema.TaggedError`**
([`Schema.ts:15125`](~/a/Effect-TS/effect/packages/effect/src/Schema.ts#L15125)):

```ts
export class Blocked extends Schema.TaggedError<Blocked>()("Blocked", {
  opId: Schema.String, reason: Schema.String
}) {}
```

`return yield* new Blocked({...})` fails the gen with a typed error that is
also serializable data (`{"_tag":"Blocked","opId":…}`). *Tested.*

**5. Schema-encoded inspection — `Schema.Struct` + `Schema.encodeSync`.**
`Schema.encodeSync(opDescriptorSchema)(op)` validates and projects the
descriptor to plain JSON, **dropping fields not in the schema** — inspection
output is schema-shaped by construction. *Tested* (S1 tree below).

**6. Outcome classification — `Effect.runPromiseExit` + `Cause`**:
`Exit.isSuccess`, `Cause.findErrorOption(exit.cause)` (typed failure) vs
`Cause.pretty` on a Die (defect). A plain `throw` inside the interpreter is a
defect, never a typed failure. *Tested* (S4).

Also verified at runtime: `Effect.forEach(children, (c) => c)` runs
Effect-valued children sequentially; `Effect.promise` wraps `node:fs/promises`
work.

## Output evidence (condensed; full tape in the capture)

Static inspection, execution-free and schema-encoded (S1) — the composite of
two independently contributed modules:

```json
{ "type": "group", "id": "apply.healthy", "tags": ["apply"], "children": [
  { "type": "group", "id": "apply.net", "children": [
    { "type": "op", "id": "iface.ens3.network", "kind": "write-file",
      "concern": "realize", "tags": ["systemd-networkd","dropin"],
      "material": { "root": "networkd", "path": "10-ens3.network" },
      "payload": { "bytes": 87, "expectedHash": "f426bf40…" } }, … ] } ] }
```

with the assertion `describeStatic ran no gen bodies, handlers, layers, or
policy checks` passing on live counters. The same `describeStatic` on an
`Effect.gen` program returns
`{"type":"opaque-effect","note":"…no truthful static description exists; display the boundary instead"}`.

Occurrences, not memoization (S2): yielding the *same* `Inspect` value twice
around a `WriteFile` gives `missing` → `present` with a real sha256, and the
tape shows `handler:inspect iface.ens3.observe` exactly twice — the
experiment-2 `seen`-dedup bug is structurally impossible here.

Real bytes from two modules via explicit collection (S3):

```text
scratch/project/
  networkd/10-ens3.network (87B)
  networkd/en.network.d/extra-addr.conf (114B)
  shell/helix/config.toml (71B)
  shell/starship.toml (103B)
```

Three distinct outcomes (S4):

| Fixture | Exit classification | World state |
|---|---|---|
| publish with denied tag | typed `Blocked` (`policy:DENY` before any `effect:link`) | host tree **empty** — no false artifact |
| write with stale `expectedHash` | typed `VerificationFailed` (`expected=deadbeef actual=fa8818e8…`) | bytes exist, exit failed — no fabricated success |
| interpreter `throw` | **defect** (`Error: simulated disk failure during realize` via `Cause.pretty`) | no write event |

The boundary, both halves (S5): the static prefix group is fully described
before running; the dynamic program chose the *realize* branch on fresh
scratch and the *skip* branch once satisfied. Then the rejected second
executor: stepping the same body as a "dry walk" executed the generator body
twice (counter-proven) while its fabricated inputs produced divergent
decisions (`missing→"realize-branch"` vs `present→"skip-branch"`) — neither
certified.

Layer lifecycle (S6): one run of N ops = 1 acquisition; two runs = 2.

## Tested vs merely proposed

**Tested here:** everything quoted above — yieldable descriptors via
`asEffect` + `use`; class-style `Context.Service` R-tracking; Layer
construction-once-per-run; explicit-collection contributions from three
modules (incl. cross-module material references); schema-encoded inspection
with zero executions; occurrence semantics; typed
Blocked/VerificationFailed vs defect; policy-before-effect ordering on the
tape; the opaque-continuation boundary; dry-walk unsoundness.

**Proposed only (not tested):** `Scope` acquire/release finalizers for
layer teardown; concurrency/streams; `Effect.fn` tracing spans for handler
observability; Schema *decode* round-trip of descriptors from persisted
bytes (only the encode direction ran); anything in the `workflow/` suite
(receipts/durability remain CFR's own concern — see corrections below);
`Layer.mergeAll` for genuinely multi-service composition (our contributions
are data, deliberately not services).

## Runtime/dependency constraints

- **No install required.** The v4 package's `exports["."]` points at TS
  source; Node ≥22.18/24.11 type-strips it (we ran Node v26.6.0). Prototype
  imports the pinned archive checkout directly — zero changes to compfuzor's
  root manifests, zero network.
- **Vanilla tsgo sufficed** for this subset: the repo's
  `@typescript/native-preview` typechecked the entire imported effect src
  tree under `--strict` with no errors from the archive (the effect repo
  patches tsgo for its own dev workflows; consumers apparently don't need it
  for ordinary use).
- **Strip-only restrictions apply to our code**: no TS parameter properties
  (classes declare fields explicitly); no enums/namespaces.
- **v4 is `4.0.0-rc.117`, unreleased**; the rc line is moving (checkout commit
  is from 2026-09-26). APIs used here are `@since 4.0.0` public surface, but
  pin an exact revision if the draft leans on them.
- One honest cast remains: the interpreter's dispatch switch returns
  `Effect<any, OpError>` and is cast to `Effect<A, OpError>` at the service
  seam — per-op success typing survives the seam, but the interpreter body is
  not exhaustively typed per op kind.

## Corrections to prior Effect material

Against [`effect-material0.glm53.md`](/design/compfuzor-runtime/effect-material0.glm53.md):

1. **"Layer is not a contribution registry" — confirmed.** One key, one slot;
   duplicate/precedence semantics are service-composition questions. Our
   additive contributions are **arrays of op data**, concatenated explicitly
   by the consumer (`[...netdropins.ops, ...shellenv.ops]`); the single
   `MaterialRuntime` key is never replaced or duplicated per module. This
   matches material0's own hedge ("collect-many needs collection-typed
   services") and sharpens it: the collection lives in **plan data**, not in
   service shape.
2. **"Effectable doesn't make arbitrary Effect.gen statically walkable" —
   confirmed, now executable.** `describeStatic` on any stock Effect (e.g. an
   `Effect.gen` continuation) can only say *opaque*, and the dry-walk
   experiment shows prefix-extraction both runs author code and fabricates
   branch decisions. Material0's §1 mapping ("authoring stays ordinary TS…
   while the value remains inspectable data") is true **for the descriptor**;
   composition beyond our own algebra is invisible, exactly as its §2 said.
3. **Workflow-as-receipt — still untested, still unstable.** Nothing here
   validates the `workflow/` suite; its "only completed activity results are
   memoized… side effects before suspension can repeat" caveat remains
   prior-scan reading, not evidence. Do not let the draft lean on it.
4. **New fact material0 lacked:** class-style service keys type `R` as the
   class instance type (not the key string), and function-style keys default
   their identifier to the shape — class-style declarations are the pattern
   that actually tracks requirements.

## What this suggests for the parent's draft (not a competing draft)

- **The core seam holds:** descriptors-as-`Effectable.Class` +
   one interpreter service + explicit collection of op data reproduces the
   experiment-1..4 findings on Effect primitives — choose-implementation
   (Layer binding) separated from collect-contributions (data arrays),
   occurrence semantics, domain-owned interpretation, policy as a bound
   service consulted before mutating primitives. The draft can treat
   `MaterialRuntime`-shaped layers as the "invocation context binds chosen
   implementations" mechanism and keep contribution in plan data.
- **Inspection story:** describe *our* algebra (ops, groups) schema-encoded,
   and render `Effect.gen` tails as an explicit opaque boundary with a known
   prefix — the exact display experiments0 asked for ("dynamic continuation
   may expose only a known prefix before execution; display that boundary").
   Reject any dry-run/walk-the-generator planner: it is a second executor
   whose output is uncertifiable (S5).
- **Outcome taxonomy maps cleanly:** `Blocked` (pre-effect policy denial),
   `VerificationFailed` (ran, postcondition false), defects (Die), success
   with verified postcondition — all four observed distinctly in one demo.
- **Durability stays ours:** Layer memoization is per-build only; receipts,
   cross-process replay, and fresh-process health remain CFR concerns on top
   of Effect, not inherited from it.
- **Risks to carry into the decision:** unreleased rc line; TS-source-as-entry
   is unusual even if deliberate; strip-only authoring constraints; the
   interpreter-side `any` cast at the dispatch seam (soluble with more type
   discipline, worth not hiding).

## Cross-references

- [`experiments0.gpt6a.md`](/design/compfuzor-runtime/experiments0.gpt6a.md) —
  probe mandate; the "compare explicit planning methods and effect-based
  interpreters, explaining where each loses truthful inspection" ask this
  experiment answers half of.
- [`experiment4.sxh.md`](/design/compfuzor-runtime/experiment4.sxh.md) — the
  registration/dispatch seam and occurrence/receipt semantics re-tested here
  on Effect primitives; its "proof-coverage regressions" (no inspectable
  composition before execution) are what `describeStatic` + the opaque
  boundary restore.
- [`effect-material0.glm53.md`](/design/compfuzor-runtime/effect-material0.glm53.md) —
  prior source scan; overclaims corrected above where tested.
- [`/design/compfuzor-runtime/composition-problem0.gpt6a.md`](/design/compfuzor-runtime/composition-problem0.gpt6a.md) —
  the operator brief behind the sequence (read via experiments0's summary).
- [`/.test-agent/cfr-effect/experiment0/README.md`](/.test-agent/cfr-effect/experiment0/README.md) —
  prototype layout and reproduction commands.
