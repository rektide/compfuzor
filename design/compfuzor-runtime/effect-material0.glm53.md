---
type: ResearchMaterial
title: Effect-TS material for the CFR backbone discussion
description: File-and-line catalog of Effect mechanisms (Effectable primitives, Context/Layer, durable workflows) mapped onto the CFR runner/composition seams from the four experiments. Material, not decisions.
resource: /design/compfuzor-runtime/effect-material0.glm53.md
tags: [compfuzor, runtime, effect, effectable, yieldable, composition, research]
status: draft
generated: { by: 'model:glm53 (GLM 5.3 max via ZAI Coding Plan)', at: 2026-09-26 }
verified: { by: unverified }
stale_after: 2026-12-26
sources:
  - id: checkout
    resource: ~/a/Effect-TS/effect
    title: Local Effect checkout (v4 line, see caveat) — LLMS.md present at repo root
  - id: experiments
    resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Four CFR backbone experiments and parent assessments
  - id: prior-anneal
    resource: /design/config-anneal/execution-model0.gpt6.md
    title: Original runtime anneal; Effect was considered and deferred pending exactly this comparison
---

# Effect-TS material for CFR

Purpose: the operator asked how Effect-TS — specifically the "effectable /
yieldable" machinery — relates to the CFR backbone questions the four
experiments surfaced ("we need more first class data than that, but I think
it's a start"). This document gathers **material with citations**, not
decisions. Every claim below was read from the local checkout this session
unless explicitly marked as prior-familiarity.

## 0. Which Effect this is (important caveat)

The checkout at `~/a/Effect-TS/effect` is the **v4 line** (unreleased next
major): `Effectable` members are `@since 4.0.0`, `Context.Service`/`Reference`
are `@since 4.0.0`, and there is a whole `workflow/` durable-execution suite.
Several things differ from the npm-stable v3 most tutorials describe:

| v4 (this checkout) | v3 (npm stable) |
|---|---|
| `Effectable.Class` with abstract `asEffect()`; `Effectable.Prototype({ label, evaluate })` ([`Effectable.ts:32-72`](~/a/Effect-TS/effect/packages/effect/src/Effectable.ts#L32-L72)) | `Effectable` with `commit()`; `yield*` via `YieldWrap` symbol |
| `Context.Service` / `Context.Reference` keys ([`Context.ts:335-340`](~/a/Effect-TS/effect/packages/effect/src/Context.ts#L335-L340)) | `Context.Tag` |
| no `Supervisor` module in tree (verified by glob+grep) | `Supervisor` module exists (v3), fiber step observation |
| `workflow/`, `Tx*`, `reactivity/`, `cluster/` suites | absent |

v3 statements above are from prior familiarity, **not** re-verified against a
v3 checkout; if any of this informs a decision, verify v3 separately. The repo
root also carries [`LLMS.md`](~/a/Effect-TS/effect/LLMS.md) and an
`ai-docs/` tree of curated examples — both good future entry points.

## 1. Effectable / yieldable: domain data that is also a step

The module doc states the intent verbatim — this is the operator's intuition,
upstream:

> "Low-level helpers for making custom values behave like Effects. The module
> exposes a prototype builder, an abstract base class, and a mixin that let
> **domain-specific values, such as service keys or configuration
> descriptions**, be evaluated by Effect and yielded inside `Effect.gen`."
> ([`Effectable.ts:1-8`](~/a/Effect-TS/effect/packages/effect/src/Effectable.ts#L1-L8))

Mechanics, as read:

- A custom value extends `Effectable.Class<A, E, R>` and implements
  `asEffect()` ([`Effectable.ts:70-72`](~/a/Effect-TS/effect/packages/effect/src/Effectable.ts#L70-L72));
  or an existing class gains the Effect prototype via `Effectable.Mixin(klass)`
  ([`Effectable.ts:129-137`](~/a/Effect-TS/effect/packages/effect/src/Effectable.ts#L129-L137));
  or a bare primitive is made with `Effectable.Prototype({ label, evaluate })`
  ([`Effectable.ts:32-42`](~/a/Effect-TS/effect/packages/effect/src/Effectable.ts#L32-L42)).
- The runtime's `Primitive` interface: an `op` label (`[identifier]`), success
  and error continuation slots (`contA`/`contE`/`contAll`), and an
  `evaluate(fiber)` hook
  ([`internal/core.ts:365-381`](~/a/Effect-TS/effect/packages/effect/src/internal/core.ts#L365-L381),
  [`makePrimitiveProto`](~/a/Effect-TS/effect/packages/effect/src/internal/core.ts#L393-L422)).
  Effects are **plain objects with labeled ops and continuation slots** —
  continuation-passing data, not closures over a scheduler.
- `Effect.gen` is a thin wrapper that turns a JS generator into an Effect via
  `fromIteratorUnsafe` ([`internal/effect.ts:1235-1258`](~/a/Effect-TS/effect/packages/effect/src/internal/effect.ts#L1235-L1258));
  each `yield*` step is chained with `flatMap` as the iterator advances
  ([`internal/effect.ts:1409-1418`](~/a/Effect-TS/effect/packages/effect/src/internal/effect.ts#L1409-L1418)).
  Anything Effectable satisfies the iterator protocol
  ([`Effect.ts:118,244`](~/a/Effect-TS/effect/packages/effect/src/Effect.ts#L118), `EffectIterator`).

**The canonical in-tree example is `Config`** — "a recipe for extracting a
typed value": the `Config<T>` interface carries `parse(provider)` as a
first-class method *and* is itself an Effect primitive whose `evaluate` reads
the ambient `ConfigProvider` from the fiber
([`Config.ts:88-111, 126-139`](~/a/Effect-TS/effect/packages/effect/src/Config.ts#L88-L139)).
That is precisely the experiment-3/4 shape — a declaration object that is also
a runnable step, interpreted against a bound provider — in production use.

Catalog of in-tree Effectable users (all first-class domain data that is also
a step):

| Value | File |
|---|---|
| service keys themselves | [`Context.ts:271`](~/a/Effect-TS/effect/packages/effect/src/Context.ts#L271) |
| CLI command models | [`cli/internal/command.ts:76`](~/a/Effect-TS/effect/packages/effect/src/cli/internal/command.ts#L76) |
| interactive prompts | [`cli/Prompt.ts:1440`](~/a/Effect-TS/effect/packages/effect/src/cli/Prompt.ts#L1440) |
| SQL statements | [`sql/Statement.ts:1440`](~/a/Effect-TS/effect/packages/effect/src/sql/Statement.ts#L1440) |
| child-process commands | [`process/ChildProcess.ts:538`](~/a/Effect-TS/effect/packages/effect/src/process/ChildProcess.ts#L538) |
| AI toolkit calls | [`ai/Toolkit.ts:303`](~/a/Effect-TS/effect/packages/effect/src/ai/Toolkit.ts#L303) |
| durable workflow activities | [`workflow/Activity.ts:158`](~/a/Effect-TS/effect/packages/effect/src/workflow/Activity.ts#L158) |

**CFR mapping.** A contributed `Publish`, `Realize`, or `BuildConfext` could be
an Effectable class whose **fields are the declaration** (destination, mode,
selectors, provenance) and whose `asEffect`/`evaluate` dispatches through a
bound domain service from context. Authoring stays ordinary TypeScript
(`yield* new Publish(material)`), while the value remains inspectable data
with a label and serialized shape. This is the "ordinary TS authoring +
inspectable program" seam experiment 4 lacked, at the *instruction* level.

## 2. Programs as data vs. step-wise interpretation (our runner gap)

- Effects are immutable primitive objects; `Effect.gen` chains continuations
  lazily (cite above). There is **no public static plan renderer** in this
  tree: observation happens at run time via spans — `Effect.fn(name)` attaches
  a tracing span and a synthesized stack frame through FiberRefs
  ([`internal/effect.ts:1288-1363`](~/a/Effect-TS/effect/packages/effect/src/internal/effect.ts#L1288-L1363),
  `CurrentStackFrame`), and [`LLMS.md:14-18`](~/a/Effect-TS/effect/LLMS.md#L14-L18)
  prescribes `Effect.fn` for reusable functions. The v4 `Primitive` interface
  is internal, so a CFR "explain before run" over arbitrary Effects would be
  built on our **own** primitives (which is fine: our Effectable classes carry
  our data), not on a public traversal API over stock combinators.
- Generators must be **re-constructible**: `fnUntracedEager` runs the body
  synchronously when possible and, on re-execution, re-invokes the generator
  function from scratch (`fromIteratorUnsafe(evaluate())`,
  [`internal/effect.ts:1386-1424`](~/a/Effect-TS/effect/packages/effect/src/internal/effect.ts#L1386-L1424)).
  Effect's own authoring model assumes programs are values built on demand —
  matching the experiment-2/4 lesson that a program must be buildable as data
  before it is executed, not just run once.

**CFR mapping.** Effect gives us values-as-data and per-step observability
(spans, stack frames), not plan-before-run. But because our domain steps would
be *our* classes, CFR can walk/inspect its own subset before execution, and let
result-dependent continuation remain honestly dynamic — the same boundary
experiments 0-4 converged on.

## 3. Context + Layer: the selected contribution set, bindings, lifecycle

- `Layer<ROut, E, RIn>` "describes how to build one or more services for
  dependency injection… services have dependencies, can fail during
  construction, or need scoped setup and release"
  ([`Layer.ts:36-60`](~/a/Effect-TS/effect/packages/effect/src/Layer.ts#L36-L60)).
  Construction is separated from program execution; `Scope` gives
  acquire/release finalization.
- `MemoMap` memoizes **layer construction only** — "prevent[s] duplicate
  construction of the same layer instance", refcounted scopes
  ([`Layer.ts:184-256`](~/a/Effect-TS/effect/packages/effect/src/Layer.ts#L184-L256)).
  This is exactly the experiment-2 distinction, upstream: shared construction
  (choose/bind once) is *not* effect memoization (every authored call runs).
- `Context.Service` keys are string-identified service slots;
  `Context.Reference` adds a lazily computed `defaultValue` — a binding with a
  default implementation
  ([`Context.ts:304-340`](~/a/Effect-TS/effect/packages/effect/src/Context.ts#L304-L340)).
  One service per key: "choose one implementation" is native; "collect many
  contributions" is modeled as a service whose shape is a collection
  (cf. `Layer.mergeAll` at
  [`Layer.ts:1243`](~/a/Effect-TS/effect/packages/effect/src/Layer.ts#L1243),
  `Layer.unwrap` at
  [`Layer.ts:1174`](~/a/Effect-TS/effect/packages/effect/src/Layer.ts#L1174),
  `provideMerge` at
  [`Layer.ts:1547`](~/a/Effect-TS/effect/packages/effect/src/Layer.ts#L1547)).
  Duplicate-key and precedence semantics between layers were not traced this
  pass — worth a focused read if this informs design.

**CFR mapping.** Layer ≈ our contribution set + bindings + scoped lifecycle;
Reference-default ≈ default implementation binding; MemoMap ≈ bind-once
construction; a collection-typed service ≈ the collect channel. The
environment construction vs program execution split is the load-bearing
boundary both Effect and our experiments independently arrived at.

## 4. Result and failure vocabulary

- Errors are data and are themselves yieldable: `Cause.YieldableError`
  ([`Cause.ts:1145-1147`](~/a/Effect-TS/effect/packages/effect/src/Cause.ts#L1145-L1147)),
  `Data.TaggedError` classes
  ([`Data.ts:684-765`](~/a/Effect-TS/effect/packages/effect/src/Data.ts#L684-L765));
  the LLMS example yields a `Schema.TaggedError` directly
  ([`LLMS.md:34-48`](~/a/Effect-TS/effect/LLMS.md#L34-L48)).
- `Cause` separates typed failure / defect / interrupt
  ([`internal/core.ts:355-362`](~/a/Effect-TS/effect/packages/effect/src/internal/core.ts#L355-L362)).

**CFR mapping.** Our completed / attention / blocked / failed taxonomy maps
naturally onto typed errors (postcondition-false as a typed `VerificationError`
that a consumer interprets — the experiment-2 "observer ran fine but ready=false"
case), with defects kept distinct from policy outcomes.

## 5. Durable execution: receipts and replay, industrialized

The v4 `workflow/` suite is the closest upstream analogue to experiment 4's
receipt/persist/refresh seam:

- `Workflow`: "stable tag, schemas for payload, success, and failure, and an
  idempotency key used to derive execution ids… executed, discarded, polled,
  interrupted, resumed… compensation and cleanup helpers, suspension support"
  ([`Workflow.ts:1-94`](~/a/Effect-TS/effect/packages/effect/src/workflow/Workflow.ts#L1-L94)).
- `Activity`: wraps an Effect with success/error **schemas** "for durable
  execution"; "only completed activity results are memoized. If the activity
  suspends… its body runs again when the parent workflow replays. Side effects
  before the suspension can repeat; make those side effects idempotent"
  ([`Activity.ts:120-191`](~/a/Effect-TS/effect/packages/effect/src/workflow/Activity.ts#L120-L191)).
  That caveat is, verbatim, our no-implicit-memoization argument.
- `WorkflowEngine` is a **pluggable engine interface**: `execute`, `poll`,
  `interrupt`, `interruptUnsafe`, `resume`, `activityExecute`,
  `deferredResult`… with storage backends behind it
  ([`WorkflowEngine.ts:95-169`](~/a/Effect-TS/effect/packages/effect/src/workflow/WorkflowEngine.ts#L95-L169));
  `DurableClock`, `DurableDeferred`, `DurableQueue` make time and side channels
  replayable; `WorkflowProxy`/`WorkflowProxyServer` carry execution across
  processes (cross-process seam, cf. experiment 4's fresh-process requirement).

All marked `@stability unstable` — treat as design precedent, not an API to
depend on.

## 6. Adjacent material worth knowing exists

- `Schema` used as the declaration-validation layer throughout (`Schema.Top`,
  `Constraint`, codec JSON) — typed declarations with round-trip encodings.
- `Config`/`ConfigProvider` split: recipe vs. pluggable interpreter — the same
  declaration/interpreter split as our domain data vs. bound implementation.
- `Tx*` modules (`TxHashMap`, `TxHashSet`, `TxSemaphore`): STM-style
  transactional structures ("checks and updates can commit atomically") —
  precedent if CFR ever wants transactional write sets.
- `reactivity/` (atom registry with explicit batch commit phases) and
  `cluster/` (entities, snowflake IDs) exist in this tree; not yet read.
- `ai-docs/` curated example suite (services, layers, testing, streams) and
  root [`LLMS.md`](~/a/Effect-TS/effect/LLMS.md) authoring guidance.

## 7. Gaps (materially true, decision-free)

1. **No public plan-before-run traversal.** Inspectability is at the
   instruction level (our own Effectable classes) and at runtime (spans);
   rendering an assembled plan is CFR's own job.
2. **No policy/bypass plane.** Nothing like compile/apply/host-runtime deny
   rules or bypass env vars; supervision-as-module is gone in v4. Policy would
   be our layer around execution (or FiberRefs + custom wrappers).
3. **One service per key.** Collect-many needs collection-typed services;
   inter-layer precedence semantics unverified here.
4. **Construction memoization ≠ execution memoization** — favorable, but means
   receipts/durability are a separate concern (workflow suite) with an
   idempotence burden documented on the caller.
5. **v4 is unreleased**; workflow/cluster/reactivity are unstable; adopting
   Effect at all is an architecture/dependency decision outside this scan.
   History: the original anneal deferred Effect pending a use-case comparison
   ([`execution-model0.gpt6.md`](/design/config-anneal/execution-model0.gpt6.md));
   this document is that homework, not a verdict.

## Cross-references

- [`experiments0.gpt6a.md`](/design/compfuzor-runtime/experiments0.gpt6a.md) —
  the four probes and the identified runner seam this material speaks to.
- [`experiment2.sxh.md`](/design/compfuzor-runtime/experiment2.sxh.md) /
  [`experiment4.sxh.md`](/design/compfuzor-runtime/experiment4.sxh.md) —
  choose-vs-collect, occurrence semantics, receipts, cross-process evidence.
- [`composition-problem0.gpt6a.md`](/design/compfuzor-runtime/composition-problem0.gpt6a.md)
  — the brief; note Effect contributes the instruction-level seam, not
  contribution-set discovery, naming, or CLI semantics.
- [`apply-flow0.glm53.md`](/design/compfuzor-runtime/apply-flow0.glm53.md) —
  manual apply stays manual; Effect's typed-failure model supports "observer
  ran, postcondition false" without conflating invocation failure.
- [`execution-model0.gpt6.md`](/design/config-anneal/execution-model0.gpt6.md)
  — where Effect was considered and set aside pending this comparison.
