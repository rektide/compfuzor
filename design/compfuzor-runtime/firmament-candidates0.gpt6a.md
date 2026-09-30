---
type: ArchitectureResearch
title: Firmament ideas for an Effect-native Compfuzor runtime
description: Candidate borrowings ranked by practical CFR value, Effect naturalizability, and the additional semantics CFR would need to own.
resource: /design/compfuzor-runtime/firmament-candidates0.gpt6a.md
tags: [compfuzor, runtime, firmament, effect, configuration, state, provenance, reactivity]
status: draft
generated: { by: 'model:gpt-6-astra', at: '2026-09-30T01:09:01-04:00' }
stale_after: 2026-10-30
sources:
  - resource: /design/compfuzor-runtime/effect-draft2.gpt6a.md
    title: CFR native Effect contributions, extensible init, mutable run data and history
  - resource: /home/rektide/src/firmament/doc/architecture/overview.md
    title: Firmament current successor architecture, checked against local source
  - resource: /home/rektide/src/firmament/doc/architecture/status.md
    title: Implemented successor, frozen legacy and proposed capability boundaries
  - resource: /node_modules/effect/package.json
    title: Installed Effect 4.0.0-rc.118; source inspected for mappings below
---

# Firmament candidates for CFR

## Finding

**Firmament offers a very useful model of attributable, changing inputs for the
Effect runtime in draft2. Most of the valuable first borrowings fit ordinary
Effect services; its strongest live-sharing guarantees require a substantial
domain coordinator even when implemented entirely in Effect.**

The particularly promising combination is **mutable workspace + retained source
contributions + bound input observations**. It would let contributors change
shared state normally while explaining what each invocation actually used, why
a value won, and whether a previous derived result is still applicable.

This inquiry answers the operator's request for candidate ideas and especially
their **Effect naturalizability**. Recommendations are choices to discuss, not
an accepted expansion of draft2. Source inspection used the local Firmament
working tree, whose HEAD was `e68f65f60a3bfdd388715b55608c48dfaf8acfe9`, and
Compfuzor's installed Effect **4.0.0-rc.118**. No implementation probe or test run
was performed for these proposed integrations.

Firmament has three bodies of material with different standing:

- **Current:** retained composition and the in-memory live engine, including
  queries, shared acquisition, dynamic support and bounded reader retention.
- **Legacy:** frozen `state` and `ops`; useful sources for history and edit
  semantics, but not the engine behind today's live behavior.
- **Proposed:** successor durability, designated writes, richer readiness and
  other destination capabilities. Their presence in a design is not evidence
  of an implementation. See the [status map][F-status].

## How to read the tables

**High fit** means the idea sits naturally in Effect's data/service/execution
model. It does not mean Effect implements its whole contract. **Medium fit**
means useful primitives exist but a consequential CFR protocol remains.
**Low fit** means a literal transplant would compete with the chosen runtime
model or require adopting much of Firmament's coordinator.

“First” identifies the strongest additions to draft2's next design/probe;
“Explore” identifies a valuable focused follow-up; “Later” names a capability
whose justification depends on broader use. Costs are relative semantic and
implementation costs, not time estimates.

## 1. Strongest candidates for the existing draft

| Candidate and Firmament standing | What it buys Compfuzor | Effect naturalization and remaining work | Judgment |
|---|---|---|---|
| **1. Capture once, compose retained data** — Current [fragment][F-fragment] | Environment, deployment state and MCP/drop-in inputs become explicit acquisition results. OpenCode and mcp-cli can assemble different answers from the same capture without silently reopening files. | **High / small–medium.** Capture with native Activities; return schema-backed owned data; compose through deterministic functions or Effects with no external reads. CFR defines the captured representation and its codec. Workflow reuse must reuse captured data, not rerun acquisition hidden in a reducer. | **First.** Excellent extension of init/load and assembly. |
| **2. Complete, individually attributable source contributions** — Current [composition][F-compose] | Replacing one source can reveal lower-priority values; no need to invent inverse patches against a flattened winner. A contributor can deliberately edit another contribution through the shared service. | **High / medium.** Keep an ordered source map in `RunData`, with `Ref`/`SubscriptionRef` behind the service and schemas at its boundary. CFR owns source identity, order and effective-value derivation. Use this for layered fields, not every scalar. Removing a contribution changes composition; it is not filesystem pruning. | **First.** The most valuable refinement of the “open bag.” |
| **3. Field-specific merge semantics and ordered overlays** — Current [relations/profiles][F-compose] | Defaults, local overrides, additive argument lists and keyed server records can express different conflict rules. Ordered profile selection could later represent reusable host/user/channel overlays. | **High as domain code / medium.** Effect Schema describes and validates the inputs; a pure reducer defines precedence. `ConfigProvider.orElse` is path fallback, **not** Firmament's six relations or ordered profile algebra. Choose rules per field; array concatenation, replacement and keyed merging are materially different. | **First** for explicit merge rules; **Explore** plural profiles when a consumer needs them. |
| **4. Winner explanation and decision provenance** — Current [explanation][F-origin] | Answer “why this command/environment/server setting?” with source, writer occurrence, merge rule and revision. Preserve why an init selector chose a source even if the selecting value later changes. | **High / medium.** Schema-backed provenance alongside values; invocation/history services reference it. Effect annotations/spans identify execution but do not automatically track value origins. Field-level attribution is cheap enough to start; nested winner tracking needs reducer support. Firmament itself does not retain a full shadow history. | **First.** Especially useful with native + opaque BINS coexistence. |
| **5. Declared input projections and captured read sets** — Current [query model][F-query] | Build work declares precisely the settings it consumes. An unrelated setting change need not invalidate a derived config. Bound inputs become an explainable record, rather than an opaque closure over `RunData`. | **High for static binding / medium.** Add schema-backed field/path selectors to draft2's input-binding annotation; resolve them from one workspace revision. Effect's `R` service requirements identify services, not field reads. Runtime read tracking requires an explicit service API; it cannot discover ambient reads in arbitrary TS or shell. | **First.** Strengthens an existing draft2 interface rather than adding another authoring language. |
| **6. Atomic revision-checked edits with stable change identity** — Current input CAS; richer batches/idempotency in [legacy state][F-state-layer] | Parallel or delayed contributors cannot accidentally overwrite newer state. Retried delivery of one logical edit can be distinguished from a new intentional mutation. | **High / medium in memory; larger durably.** `Ref.modify` can atomically validate/replace one aggregate state. Schemas describe changes and typed conflicts. Cross-field atomicity needs one transaction boundary, not several unrelated refs. Durable changes need a transactional store and replay protocol; refs and Activity caching do not provide that. | **First** for explicit revisions/change identity; prove durable and partial-write behavior at draft2's checkpoint. |
| **7. Absence, acquisition failure and accepted data are distinct** — Current [acquisition][F-acquire] | Deleting an optional override can reveal defaults; malformed JSON must not quietly erase it. Status can distinguish “not present,” “failed to read,” and “last accepted value.” | **High / small.** Tagged data for successful present/absent observations; typed Effect errors for failed acquisition. Retain previous accepted data separately from the attempt result. `ConfigProvider` already distinguishes missing paths from source errors; CFR extends that distinction to whole-source capture. | **First.** A small contract with large practical value. |
| **8. Exact observation identity versus value equality** — Current output coordinates; exact multi-history frontiers in [legacy views][F-frontier] | Two runs can produce equal bytes from different sources/code revisions. Avoid rebuilding consumers that care only about values while retaining exact lineage for history and publication. | **High for records / medium.** Keep separate content identity, input/source revision references, occurrence identity and semantics version. Effect `Equal`/cache keys can use the chosen equivalence, but CFR must define it. Durable reconstruction additionally needs retained inputs and resolvable code/dependencies. | **First** for identity distinctions; **Later** for a generalized frontier/history store. |

## 2. Bigger capabilities that still have a natural Effect shape

| Candidate and Firmament standing | What it buys Compfuzor | Effect naturalization and remaining work | Judgment |
|---|---|---|---|
| **9. Explicit shared acquisition with isolated source inputs** — Current [LiveLayer][F-layer] | One MCP inventory or repository inspection can feed different consumer pipelines, each with its own composition. A recipient's unrelated override cannot silently alter how the common source is acquired. | **High for fixed bindings / medium.** `Cache` shares finite lookups; `RcMap` shares scoped continuing resources; `LayerMap` exposes keyed service contexts. CFR defines stable source/binding keys, dependency identity and refresh policy. Sharing a client or Layer construction alone does not deduplicate its queries. | **Explore early.** Strong payoff for the “one input, two consumers” example. |
| **10. Reactive derived views over mutable run data** — Current live composition | A status/preview/config view updates when relevant fields change; contributors keep ordinary mutation APIs. This can reduce manual propagation between settings and derived values. | **High for process-local derivation / medium.** Installed Effect has `Atom`, `AtomRegistry`, `Atom.family`, effect/stream-backed atoms and `Reactivity`. A registry can scope derived state to a run. CFR still owns coherent snapshots, provenance, durable history and any Firmament-style applicability proof. These Effect APIs are marked unstable. | **Explore.** A serious native option, especially for observation and pure assembly. |
| **11. Shared source lifetime driven by demand** — Current [lifecycle][F-life] | A watcher/query survives while at least one consumer needs it; an inspector does not accidentally keep work running forever. | **High / small–medium.** `Scope`, finalizers, scoped fibers and `RcMap` give a close match. Define what acquires a lease and whether idle retention is allowed. Ending a lease releases runtime resources; it does not uninstall provisioned artifacts. | **Explore with #9.** Much of Firmament's host/runtime machinery is already Effect's job. |
| **12. Notices trigger recapture, not mutation** — Current [native acquisition][F-acquire] | Watch mode can coalesce edits, retry failures and re-read a complete source while preserving source semantics. A filesystem event is not mistaken for new config contents. | **High for execution / medium for policy.** Streams, queues, schedules and scoped filesystem watches are natural primitives. CFR/source adapters still decide full-capture boundaries, notice-during-capture behavior, retry budgets and evidence. Generic debounce or `Reactivity` invalidation does not implement checked filesystem capture. | **Explore** when adding a watch/session mode. |
| **13. Reject stale completions with a generation fence** — Current [acceptance gate][F-accept] | A slow capture started under old settings cannot overwrite output after the root, target or binding changed. Cancellation becomes an optimization, not the only correctness mechanism. | **High / medium.** Capture a binding generation; check it atomically when accepting a result. Scoped interruption helps stop old fibers but cannot undo completed external work. Publication to external systems needs its own conditional-write/serialization contract. | **Explore before** concurrent refresh or live source replacement. |
| **14. Explicit preview/settled/retained reader policy** — Current [retention][F-retention] | A status display may show a provisional or bounded last-good answer while an assembly/publication consumer requires suitable current inputs. One source can serve readers with different needs. | **Medium / medium–large.** Schema-tagged observations plus clocks, streams and timers fit Effect. `AsyncResult` gives loading/result state, not these policies. CFR must track support compatibility and original acceptance age; repeated failures or new subscribers must not reset the fallback window. Settled is not proof of source freshness or external installation. | **Explore** for live consumers; avoid making every finite BINS invocation participate. |
| **15. Snapshot + cursor + explicit gap inspection** — Current [execution record][F-record] | A CLI/UI can inspect current work and follow changes without missing an update between the two. A slow follower learns when it must reseed. | **High / medium.** SQL/event-journal records plus a wakeup stream; readers consume stored records after a captured cursor. CFR must make the snapshot/cut coherent and define retention/gaps. `PubSub` alone is not a durable log. Firmament's implementation is bounded in-memory history; CFR's draft2 durability requirement remains stronger. | **Explore** as the history read interface; keep durable writes in the first runtime contract. |

## 3. Powerful ideas whose adoption changes the architecture

| Candidate and Firmament standing | What it buys Compfuzor | Effect naturalization and remaining work | Judgment |
|---|---|---|---|
| **16. Dynamic support: discover dependencies, partition shared work, remember blocked demand** — Current [support model][F-support] and [comparison code][F-compare] | Work can discover a new relevant input halfway through execution without exposing its specialized output to incompatible consumers. A blocked consumer remembers its learned requirements even when no worker remains. | **Medium as an Effect service, low as a direct upstream substitution / large.** Atoms track reactive dependencies; caches share by key. Neither supplies Firmament's ordered demand contracts, split-before-delivery, immutable original support, reattachment rules and generation checks. CFR would build that state machine and its diagnostics. | **Later, deliberately.** First try static input projections and independent rebinding; pursue the full protocol if expensive shared continuing work actually learns dependencies. |
| **17. Named accepted-output dependencies** — Current [named outputs][F-output] | Depend on a particular occurrence having accepted an output, even if its value is unchanged. This separates a production prerequisite from a value read. | **High for explicit finite sequencing; medium–low for live graph semantics / medium–large.** Normal Workflow sequencing/results and occurrence-qualified artifact references cover the first need. Live invalidation, conditional edge changes, remembered waits and cycle checks require a coordinator. Firmament's facts are opaque coordinates, not value exports. | **Borrow the distinction now.** Add the live graph only for a concrete need beyond draft2's stages/children. |
| **18. Designated writes and incorporation receipts** — Proposed richer write system; current input receipts [destination][F-writes] | Edit an explicitly chosen input/override instead of guessing the write target from the winning value. Distinguish native write success, recapture, inclusion in a view and effective winning value. | **High for target-bound Activities / medium–large for receipts.** Schemas, typed outcomes and workflows fit well. CFR/native adapters own conflict checks, ambiguous outcomes and operation IDs. Generic Workflow retries cannot turn a foreign write into exactly-once delivery. | **Explore** for CONFIG input editing/publication. Very relevant semantics even though the richer Firmament implementation is future work. |
| **19. Subject-aware grants and revocation in support** — Current, qualified [status][F-status] | A multi-user runtime could control which subjects may share computation or inspect a whole answer and revoke later use. | **Medium / large.** Policy services and schema-backed grants are ordinary Effect. Service requirements and scoped provision are not access control or a native-code sandbox. Sharing keys, existing attachments, histories and reader disclosure must all participate. Firmament's cross-recipe LiveLayer enforcement is itself deferred. | **Later** unless CFR gains genuine multi-user authority boundaries. |
| **20. General operation-intent interpreter / second recipe engine** — Legacy [ops][F-ops] | Offers pre-step snapshots, proposed edits and attributed outcomes. A literal port would also add an instruction language and execution authority. | **Low as a transplant.** Native Activities/Workflows already own execution. Borrow specific data-only changes and before/after snapshots into services; leave branching, sequencing and host work as authored Effect. A pure configuration reducer is compatible with this boundary. | **Borrow semantics, not the engine.** This would otherwise reverse draft2's strongest choice. |

## The important Effect boundary

### Three tempting equivalences that do not hold

1. **Firmament layer ≠ Effect `Layer`.** The former is a reusable contribution
   with an acquisition/support boundary; the latter constructs services and
   manages their dependencies and resources. An Effect Layer can provide the
   source service that implements a Firmament-like contribution.
2. **Reactive dependency ≠ recorded support.** Atom dependencies answer what
   to recompute. Firmament support additionally records what an accepted result
   observed, what a particular consumer now requires, and why reuse is allowed.
3. **Activity replay ≠ semantic cache reuse.** Replay reuses the outcome of an
   identified logical occurrence. A cache shares work for equivalent declared
   inputs. Neither grants permission to suppress a second intentional install.

This makes **#9 and #10 more naturally Effect-native than a primitives-only
assessment would suggest**, but it does not make #16 free. The most useful
upstream evidence is:

| Installed Effect source | What it really supplies |
|---|---|
| [`Ref`](/node_modules/effect/src/Ref.ts), [`SubscriptionRef`](/node_modules/effect/src/SubscriptionRef.ts) | Atomic in-memory state transformations; serialized observable updates. Durable history and cross-ref transactions remain separate. |
| [`ConfigProvider.orElse`](/node_modules/effect/src/ConfigProvider.ts#L481-L570) | Missing-path fallback; a source error propagates. Not a retained, provenance-bearing composition algebra. |
| [`Layer` memoization](/node_modules/effect/src/Layer.ts#L182-L233), [`Cache`](/node_modules/effect/src/Cache.ts) | Sharing service construction versus sharing keyed lookup outcomes; distinct mechanisms. |
| [`RcMap`](/node_modules/effect/src/RcMap.ts), [`LayerMap`](/node_modules/effect/src/LayerMap.ts) | Keyed scoped acquisition, shared in-progress resources, reference-counted release and keyed service contexts. |
| [`Atom`](/node_modules/effect/src/reactivity/Atom.ts#L164-L207), [`AtomRegistry`](/node_modules/effect/src/reactivity/AtomRegistry.ts) | Dependency-tracked values, Effect/Stream integration, independent registry state and lifecycle. No built-in CFR replay/acceptance contract. |
| [`Reactivity`](/node_modules/effect/src/reactivity/Reactivity.ts#L153-L219), [`AsyncResult`](/node_modules/effect/src/reactivity/AsyncResult.ts) | Key invalidation/coalesced query reruns; observable async result/loading state. Neither establishes freshness or support-compatible fallback. |
| [`WorkflowEngine`](/node_modules/effect/src/workflow/WorkflowEngine.ts), [`EventLog`](/node_modules/effect/src/eventlog/EventLog.ts) | Managed execution/result reuse and a separately integrated event log. EventLog handles before committing; it is not automatically a write-ahead transaction around host effects. |

## A coherent first integration

The useful design seam is inside draft2's **`RunData` and invocation binding**.
For layered configuration fields, retain source contributions and derive their
effective value; for ordinary fields, retain normal set/update semantics.
Both remain accessible through the same mutable typed service.

An invocation binds an immutable input observation from the workspace state at
that point. Later contributors can still mutate the workspace; the next
invocation sees those changes. This is a per-invocation observation boundary,
not a freeze of the run.

For OpenCode and mcp-cli, the resulting story is:

1. An init Activity captures MCP records as an ordered, schema-backed source
   result with origin and capture outcome.
2. A contribution changes the server selection or overrides command settings
   through `RunData`. The write has occurrence identity and a revision.
3. Each consumer binds its own projection and composes its own output. They
   can share captured source data without sharing a mutable consumer result.
4. History records which source revisions, effective inputs and adapter/code
   identity produced each artifact. Equal output bytes do not erase this history.
5. Publication remains an explicit Activity. A later source change can mark the
   derived view out of date without silently rerunning installation.

These semantics also help ordinary builds: resolve workspace/toolchain settings
once for an occurrence, preserve the argument/environment observation, then let
later contributions intentionally change inputs for subsequent work. Opaque
BINS retain draft2's limitation: shell-internal reads and mutations remain opaque.

### How layered data and direct mutation meet

A concrete choice needs discussion before implementing #2: **where does a plain
`set` land for a layered field?** My preference is a named run-local edit
contribution at a declared precedence, with an explicit operation to edit or
replace another source contribution. This preserves “later writers can change
earlier values” while keeping explanation meaningful.

Removal then has two distinguishable meanings: remove an edit so lower data is
revealed, or explicitly suppress an effective key. The latter needs a defined
mask/tombstone rule if required; it must not be accidentally inferred from the
former. Existing CONFIG disable/selection behavior should determine that rule.
Non-layered fields can keep ordinary direct set/remove behavior.

### The replay constraint still applies

Source contributions and edit records do not by themselves solve draft2's
cached-Activity mutation problem. Start with capture Activities returning data,
then apply identified changes in the workflow outside the cached body. A durable
change record should bind occurrence, expected revision and validated payload;
an identical redelivery can be recognized, while different payload under the
same change identity is a conflict.

Reconstruct into a workspace at the correct workflow position. Do not restore
the final map and apply early updates against it. A SQL transaction can make
managed state/history acceptance atomic if designed that way; it does not
atomically include child-process effects. Neither Firmament's current live engine
nor its frozen memory store supplies the missing CFR durable protocol.

## What I would put in the next probe

Keep draft2's BINS/native/discovery probe, and add these focused observations:

- **Capture and layering:** one capture feeds two consumer assemblies; removing
  an override reveals the base; malformed replacement reports failure rather
  than empty success.
- **Mutation and explanation:** a later contributor changes a previous setting;
  two successive invocation bindings show the appropriate revisions and origins.
- **Replay:** reusing the capture result reconstructs the same contributions;
  repeating the same logical edit does not append another durable change.
- **Equivalence:** an unrelated field edit preserves a declared projection;
  equal bytes at a new source revision remain a distinct historical observation.

Then the most informative optional follow-up is **one explicitly shared source
with two bindings** using `RcMap`/`Cache`, plus a pure derived Atom view. Change
one binding while capture is held and prove a stale result cannot attach to it.
That tests whether useful live power can remain a small Effect service before
committing to dynamic support partitioning.

## Cross-references

- [Effect draft2](/design/compfuzor-runtime/effect-draft2.gpt6a.md) — the governing
  proposal for this comparison. Candidates refine its §§4–5 input/state model,
  §7 binding/history and §9 shared-consumer example.
- [Effect material](/design/compfuzor-runtime/effect-material0.glm53.md) — prior
  upstream scan; this pass extends it with installed rc.118 cache/resource and
  reactive-state mechanisms, and sharpens construction versus acquisition sharing.
- [Effect probe](/design/compfuzor-runtime/effect-probe0.glm53.md) — evidence that
  attributed domain data can execute through Effect services; also explains why
  inspecting arbitrary continuations cannot produce a trustworthy static plan.
- [CONFIG consumer toolkit](/doc/config/consumer-toolkit.md) — compatibility
  constraints for selection, inputs, assembly and publication. Firmament's profile
  or merge rules are candidate tools, not replacements for those established rules.
- [Firmament overview][F-overview] and [status][F-status] — establish which source
  family implements each idea. Particularly important before borrowing old state
  histories or proposed writes as if they shipped in the live engine.

## Firmament source references

Links target the inspected first-party local checkout. Its Git configuration
provided no remote URL, so these references do not invent a published location
for local successor code.

[F-overview]: /home/rektide/src/firmament/doc/architecture/overview.md
[F-status]: /home/rektide/src/firmament/doc/architecture/status.md
[F-fragment]: /home/rektide/src/firmament/src/composition/fragment.rs#L36-L99
[F-compose]: /home/rektide/src/firmament/doc/composition/model.md
[F-origin]: /home/rektide/src/firmament/src/composition/origin.rs#L28-L55
[F-query]: /home/rektide/src/firmament/src/support/query.rs#L122-L148
[F-state-layer]: /home/rektide/src/firmament/src/state/layer.rs#L447-L497
[F-acquire]: /home/rektide/src/firmament/doc/sources/acquisition.md
[F-frontier]: /home/rektide/src/firmament/src/state/view.rs
[F-layer]: /home/rektide/src/firmament/doc/live/layers.md
[F-life]: /home/rektide/src/firmament/doc/live/lifecycle.md
[F-accept]: /home/rektide/src/firmament/src/live/engine.rs#L3126-L3262
[F-retention]: /home/rektide/src/firmament/doc/live/retention.md
[F-record]: /home/rektide/src/firmament/doc/live/execution-record.md
[F-support]: /home/rektide/src/firmament/doc/support/model.md
[F-compare]: /home/rektide/src/firmament/src/live/dependency/mod.rs#L65-L143
[F-output]: /home/rektide/src/firmament/doc/support/named-outputs.md
[F-writes]: /home/rektide/src/firmament/.design/ad-astra/architecture1.gpt6a.md#L1585-L1694
[F-ops]: /home/rektide/src/firmament/OPS.md
