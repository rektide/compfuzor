---
type: ArchitectureProposal
title: CFR as an Effect-native application with first-class domain programs
description: A replacement backbone using Effect for execution and services, while CFR owns contributed descriptions, compositional program data, placement and command discovery.
resource: /design/compfuzor-runtime/effect-draft0.gpt6a.md
tags: [runtime, effect, composition, registry, confext, layout]
status: draft
generated: { by: 'model:gpt-6-astra', at: '2026-09-26' }
sources:
  - id: operator
    resource: cotail://ses_f2198adecffeZm5gWy0G9BCV3h
    title: quiet-tiger — explicit pivot to Effect after four architectural experiments
  - id: checkpoints
    resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Four experiments and parent assessments
  - id: effect-source
    resource: https://github.com/Effect-TS/effect/tree/64093976e9f595f0f9638aad5526738c78a3fa08
    title: Local Effect checkout revision used for the draft
---

# CFR on Effect: domain programs, not another runner

## 1. Decision and scope

**Effect is the execution foundation.** CFR does not build an alternative
promise runner, dependency container, cancellation system, or scheduler and
then offer Effect as a backend. CFR becomes an Effect application and library
whose additional value is **first-class, contributed domain meaning**.

The four experiments separated useful ideas but never combined open
contribution, inspectable composition, and a convincing execution runtime.
The final toy was an extensible async dispatcher; its earlier program tree had
disappeared. Effect lets us stop rebuilding the execution substrate and spend
our design effort on the information Effect cannot infer: what a contribution
means, where it participates, which materials it describes, and how users
discover and select it.

This is a new proposed architecture, not an implementation or a declaration
that the preceding prototypes are production-ready. The operator has chosen
the Effect direction; the detailed interfaces below remain reviewable.

### Upstream baseline

Target the **Effect 4 API family** in the operator's checkout,
`~/a/Effect-TS/effect`, revision
`64093976e9f595f0f9638aad5526738c78a3fa08`; its package manifest declares
`4.0.0-rc.117`. This is a source/API baseline, not an assertion about npm's
current stable tag. Pin a mutually compatible Effect/platform release or
revision when implementing; do not silently mix v3 tutorials with these APIs.

In particular use `Context.Service`, `Layer`, `Effectable.Class.asEffect`,
`Schema`, and the public platform interfaces verified in this tree. Some
adjacent modules are marked unstable. No CFR code should import
`effect/internal/*` or traverse private Effect runtime opcodes.

## 2. What we stop owning, and what we must own

| Effect owns | CFR owns |
|---|---|
| Effect evaluation, typed failures, defects and interruption | Domain outcomes: drift, blocked prerequisites, selected omissions, artifact completeness |
| Context service requirements and implementations | Contribution discovery, identity, selection, provenance, and declared provider choices |
| Layer construction, resource sharing and scoped release | Module manifests, additive contribution composition, compatibility validation |
| Sequential/concurrent effect combinators and fibers | Meaningful phase groups, program structure, dependency declarations and safe defaults |
| Platform filesystem/process interfaces and implementations | Placement, ownership, representation policy, privilege routing and target context |
| Tracing, logging, resource finalization | Stable operation/invocation identities and explanations of why work was selected |
| Schema validation and codecs | Versioned CFR/domain contracts and descriptor formats |

These are complementary responsibilities, not two execution engines. A CFR
composition lowers to ordinary Effects; Effect alone executes those Effects.

**Hard choices in this draft:** new domain implementations return Effects,
not promises; asynchronous legacy implementations are bridged at the edge.
Effect Context/Layer replaces the experimental string-keyed service locator.
Effect scopes own acquired resources. Process execution uses the Effect platform
adapter, not a second CFR child-process supervision loop. `runPromise` or
`runMain` belongs at process/embedding boundaries, not inside domain services.

## 3. The central move: descriptions that are also yieldable

An operation should not be an opaque callback with metadata attached somewhere
else. Its **invocation value** carries a stable definition reference, validated
input, target references, concerns and provenance. That value is also directly
yieldable: its `asEffect()` obtains the appropriate service and returns the
Effect that performs the operation.

This pattern is already upstream. [ChildProcess.Command][child-process]
describes a process as fields (`command`, `args`, `options`), or a pipeline as
`left`/`right`, and is itself an Effect. Evaluating it delegates to the supplied
`ChildProcessSpawner`. It is a much closer precedent than a generic task queue.
[Config][config] likewise separates a recipe from its provider and is yieldable.

For CFR, the public conceptual interface is:

```ts
// Proposed CFR interfaces, not existing exports or a checked implementation.
const publish = PublishMaterial.call({
  material: Material.ref("iface.extra-address"),
  exposure: Exposure.ref("networkd.extra-address"),
});

publish.describe();                    // pure domain invocation data
yield* publish;                       // an ordinary Effect evaluation
yield* publish.pipe(Effect.withSpan("network.publish"));
```

The definition is shared; a call binds inputs. Each evaluation is an occurrence.
Yielding the same observation value before and after a mutation runs it twice.
There is no automatic action/query memoization. Layer sharing concerns service
construction, not whether an observation or mutation should run again.

Use the public `Effectable.Class` for these values. Domain classes need not
understand fibers or Effect's primitive implementation. The detailed contract
must preserve `A`, `E`, and `R`: an invocation cannot claim `R = never` while
secretly requiring a filesystem, policy, material or publication service.

The [GX probe](/design/compfuzor-runtime/effect-probe0.glm53.md) exercised this
minimal bridge with the actual public APIs:

```ts
// Tested probe excerpt; a single material domain, not the final plugin API.
abstract class Op<A> extends Effectable.Class<A, OpError, MaterialRuntime> {
  // Subclasses carry id, kind, concern, tags, material and domain payload.
  asEffect(): Effect.Effect<A, OpError, MaterialRuntime> {
    return MaterialRuntime.use((runtime) => runtime.run(this));
  }
}
```

Class-style service keys track the class identifier in `R`, not the key string.
Use that tested style for named CFR services. Function-style keys with explicit
identifier and implementation types are also valid; class syntax is not an
upstream soundness requirement.

### Data is not necessarily an instruction

Not every contributed value should be executed. A material specification,
selection rule or exposure declaration is inert Schema-validated data. An
operation *about* it is yieldable. Avoid making `yield* material` ambiguously
mean render, publish, inspect, or read its bytes.

Public definitions may use schemas for input, output and typed failure. Those
schemas support script/CLI decoding and documentation; they do not serialize
arbitrary Effect closures or recover erased TypeScript service requirements.

## 4. More first-class data: composition is a domain value too

Effectable does **not** make the body of arbitrary `Effect.gen` statically
inspectable. The generator can choose its next operation using a result not
available yet. Registering named leaves does not make all future calls visible.

For composition that must be discoverable, CFR therefore retains a small
**program structure** as its own data. It too is Effectable, just as an
upstream piped command retains its two children and is an Effect:

| Structure | Meaning and Effect lowering |
|---|---|
| Call | One described operation invocation; delegate to the selected domain service |
| Sequence | Known ordered children; lower to sequential Effect composition |
| Group | Named selected children plus ordering/concurrency policy; resolve, validate, then lower |
| Effect body | Authored Effect implementation with a declared description; inspect as opaque/dynamic, not fake child nodes |

These are the useful initial forms, not a universal workflow instruction set.
Do not immediately encode loops, transactions, retry, fibers and every Effect
combinator in a duplicate CFR language. Normal Effect composition remains
available inside a body. Named domain operations expose additional structure
where doing so is valuable.

```ts
// Proposed CFR construction syntax. Effects execute it; CFR describes it.
const applyNetwork = Program.sequence("apply/network", [
  Group.collect("network.publish", { phase: "publish" }),
  Group.collect("network.reconfigure", { phase: "change" }),
  VerifyNetwork.call({ selection: Selection.current() }),
]);

const inspectAround = Effect.gen(function* () {
  const before = yield* InspectNetwork.call({ selection });
  yield* applyNetwork;
  const after = yield* InspectNetwork.call({ selection });
  return { before, after };
});
```

The sequence has a fully described structure once its groups are resolved.
`inspectAround` is valid Effect code but does not automatically acquire an
inspectable sequence from its source text. An author wanting both writes it as
a CFR sequence or supplies an honest declared outline. An outline is not an
exact compiled plan and must be labeled accordingly.

**No speculative dry-run of a generator with invented return values.**
Execution under a fake filesystem is a useful test, not proof that the real
program will visit the same branches. Do not import private opcodes to conceal
that uncertainty.

### Inspection has three honest levels

1. **Catalog:** definitions, contributions, references and relationships,
   obtainable without constructing live service Layers or running handlers.
2. **Resolved plan:** selected members, target bindings, phase order, declared
   material effects and policy decisions. Exact for explicit structures;
   dynamic or opaque sections remain marked as such. Read-only domain preflight
   may be requested separately and attributed.
3. **Execution trace:** actual calls, chosen branches, outcomes and spans.

No one level masquerades as another. Resolution snapshots selected declarations
and module versions; that does not freeze arbitrary closure state or external
files. Record those limits in provenance.

## 5. Modules contribute; Layers supply implementations

A module exports an inert description and, for native implementations, Effect
Layers and program definitions. It does not mutate a global singleton registry
on import. Built-ins, installed modules, project modules and generated
descriptors can all participate through explicit module selection.

```ts
// Proposed authoring surface, not an upstream Module API.
export default Cfr.module({
  id: "systemd.network",
  tags: ["systemd", "network"],
  materials: [extraAddressMaterial],
  exposures: [extraAddressExposure],
  contributions: [
    contribute("network.publish", publishExtraAddress),
    contribute("network.verify", inspectExtraAddress),
  ],
  programs: [applyNetwork, networkStatus],
  implementations: [Networkd.layer],
});
```

The module system collects **many declarations** and chooses **one provider per
service role**. Do not implement additive registration by supplying the same
Context service repeatedly. [Context.merge][context-merge] lets the second
context override the first for a shared key; that is not an aggregation contract.
Validate provider choices explicitly, collect records into a registry snapshot,
then provide that snapshot as a service and compose the selected Layers.

Native library callers use typed `Context.Service` keys. Schema-backed domain
contract identifiers connect external records to the matching decoder/adapter.
Dynamic plugin loading is a runtime validation boundary, not magically covered
by TypeScript's `R` type. Validate versions, advertised requirements and duplicate
identities before constructing executable environments.

Metadata loading must not acquire live Layers. TS modules remain trusted code:
their imports can execute arbitrary JavaScript. For data-only inventory, consume
generated descriptors without importing implementation modules; bind descriptors
to module versions/digests to detect stale descriptions. This is not a sandbox.

### Registry questions become library queries

The registry indexes definitions and declared program relationships, not Effect's
private instruction stream. Scripts can query the same versioned data:

- Which modules contribute to this group, and through which declaration?
- Which commands select this material or operation?
- What service role and provider does this operation require?
- Which programs declare this status operation as verification or diagnostics?
- What cannot be known until the dynamic body runs?

Related-operation links need not imply execution. `verifies`, `diagnoses` and
explicit program membership can be different relationships; avoid interpreting
an `after` metadata hint as both dependency and optional companion.

## 6. Command paths and phase groups without a filename parser as authority

An exported command address is a path of segments. Adding specificity narrows
the selected members of the same operation; removing it broadens them. Hyphens
inside a segment are ordinary characters. Existing filenames map explicitly
through the legacy adapter; they are not recursively split into a guessed tree.

```sh
# Proposed CLI; use one explicit target, not runtime executable location.
cfr --project /srv/example list apply/network
cfr --project /srv/example explain apply/network/extra-address --json
cfr --project /srv/example plan apply/network
cfr --project /srv/example run apply/network/extra-address
cfr --project /srv/example query consumers --operation network.inspect --json
cfr --project /srv/example run build/confext/network
```

A command export defines its selector and broad-run behavior. A prefix is not
permission to execute every coincidentally named operation in the registry.
Selecting a target cannot silently include other projects or change from user
to system scope. Narrowing does not disable ordering rules, verification or
execution policy.

**Phases are ordered groups within a resolved program.** For broad network
apply: all selected publication steps, then changes, then verification. Navigation
groups can cross these phases. If an operation must stay contiguous, expose a
composed call with its own internal order rather than letting an implicit
earliest-phase heuristic override a barrier.

Run groups sequentially by default. Explicit parallel groups lower to Effect's
concurrency combinators with a declared bound and failure policy. Resource
conflicts and prerequisite edges are CFR/domain validation concerns; Effect's
ability to run fibers does not certify independent work.

Use `effect/cli` and the platform runtime for the new frontend. Their command
declarations, shared flags and subcommands are upstream mechanisms, not another
hand-written argument parser. Dynamic registry selection can remain an argument
to `run`/`plan`, so every plugin need not extend the parser implementation.
Generated `apply.sh` and other compatibility entry points become thin commands
selecting the same program, not an independently composed shell implementation.

## 7. Execution policy is an Effect service, not an Effect alternative

Provide an invocation environment containing the explicit target, registry
snapshot, policy and domain Layers. Named operation evaluation checks policy
before acquiring mutation-specific resources and before invoking its handler.
Nested CFR calls use that same policy; narrowing or calling a leaf directly
cannot widen a concern-level permission.

Domain primitives carrying significant effects also check the applicable concern
so a composite does not accidentally bypass a policy check by skipping a wrapper.
Trusted TS can still call Node APIs directly: these guarantees apply to managed
operations and are not process isolation.

- `BINS_RUN_BYPASS`: suppress the Ansible-triggered execution plane, not
  generation and not every later explicit invocation.
- Concern bypass: remains effective for nested matching mutations; independent
  observation has its own policy.
- Optional suppressed member: an explicit `Skipped` result, recorded by the
  aggregate.
- Required suppressed producer/preparation: typed `Blocked` failure; downstream
  artifact work does not run or report completion.
- Successful observation of drift: domain result data; a verification consumer
  can turn it into a typed verification failure without calling the observer
  itself broken.
- Defects and interruption: preserve Effect's distinction; do not flatten them
  into `false` or a normal skipped outcome.

Use Schema-tagged errors for cross-boundary failures and structured domain
results for observations. The CLI adapts them to documented exit codes; exit
codes are not the library's internal result model. Do not automatically retry
host mutations because Effect makes retry convenient.

Layers construct services, not deployments. Importing a module or building an
inspection environment must not publish files, configure networking, or install
the runtime as a service-construction side effect. Effect scopes finalize
acquired handles and temporary resources; they are not automatic rollback of
irreversible host changes.

## 8. Placement and confext as the first substantive domain

Material identity, byte location and consumer destination remain separate data.
The Effect pivot does not erase the single-tree problem behind an effectful
`writeFile` call.

```text
material declaration + selected layout
               ↓
resolved byte owner and exposure relationships
       ├── material realization / inspection
       ├── publication / exposure inspection
       └── selected artifact projection / artifact inspection
```

A layout selects which root owns bytes and how another root exposes them:
system-owned bytes with project-facing links, or project-owned bytes with
system-facing publication. Link/copy constraints remain explicit per consumer;
the iface playbooks' copy-only delivery must not silently become a private-tree
symlink merely because that is representable. Existing trees require deliberate
migration; changing a profile does not authorize moving or deleting them.

**Confext is a projection, not execution of the installer under another root.**
Its operation consumes an explicit selection of material and destination data,
validates readiness and modes, and produces a directory or chosen image form.
No network apply, host publication, confext merge, or activation follows.

Selection uses ordered include/exclude/reinclude rules over canonical intended
destinations, with an explained decision for each candidate. Preserve the user's
interest in a full gitignore-shaped selector; specify grammar and escaping before
implementation rather than treating the probes' limited wildcard matcher as final.
Tags and material IDs can be separate explicit selector dimensions. Filesystem
enumeration tools may feed candidates, but their ambient ignore files must not
silently change declared selection.

Reuse existing material by default in `build/confext`. An explicit larger build
program can first request realization, but packaging does not secretly regenerate.
A material service may use durable receipts or an adapter over existing build
evidence. Do not require every legacy project to have been built by CFR merely
to package its files. Describe what is known versus assumed by each adapter.

Validate destination collisions after root resolution, mode/ownership policy,
symlink treatment, and output identity. Confext release metadata lives under
`etc/extension-release.d/extension-release.<artifact-name>`. The prior experiment's
custom-name error is a reminder that correct shape is a domain contract, not an
effect-runtime feature. Directory, filesystem-image, and DDI outputs are all
within build scope; installation remains outside this task.

Effect Schema encodes material/receipt contracts; filesystem and process services
perform the work; scoped staging supports cleanup; operation spans carry selection
and source identities. These are direct uses of Effect, not reasons to embed a
universal filesystem graph in its runtime.

### Durable execution is a different question

Effect Workflow/Activity is useful precedent but **not the default CFR runner**.
A saved successful activity result does not prove today's file bytes, permissions
or host state still match it. Material receipts and live observation remain
domain concerns. Replaying or resuming a long operation is a separate capability,
with explicit idempotency and versioning requirements; ordinary status must not
become a memoized activity by accident. STM likewise does not make filesystem
writes transactional.

## 9. Shared runtime, bootstrap and early project preparation

The runtime can live in an ordinary Compfuzor checkout. A built-in described
`runtime.install` operation uses the selected publication/filesystem services
to expose its executable globally. Invoke it locally first; no Ansible or
already-installed global executable is required by that operation. A playbook
can invoke the same operation after ensuring host prerequisites.

The global entry executes the same Effect program machinery. Runtime checkout,
lexical invocation path and selected deployment root are independent context
values. Bootstrap inputs come from outside a not-yet-created project. Node and
a usable checkout/artifact are genuine prerequisites, not recursively solved by
the absent global command.

Project preparation is an explicit program before the first checkout/material
write. A selected storage service can implement ordinary directory or btrfs
subvolume preparation. Both expose the same preparation contract while preserving
their own validation and existing-directory policies. Do not claim the earlier
marker-based probe implemented btrfs. Snapshots are later explicit operations.

The checkout may distribute one bundled runtime artifact and its built-in modules;
external contributed TS modules need a supported loading/dependency contract.
Do not copy the runtime into every project by default, or assume a global npm
installation automatically makes `effect` resolvable from arbitrary project
modules. The build/distribution strategy must ensure one compatible Effect
contract family across host and contributed modules; resolve this before public
plugin publication. Versioned data-only/script adapters remain another route.

## 10. Replacement shape and implementation direction

Suggested domain grouping, not a mandated file-by-file migration:

```text
files/runtime/
  contributions/  module descriptors, collection, resolution, registry queries
  programs/       Effectable calls/groups/sequences, structural inspection
  execution/      invocation policy, outcomes, tracing and process entry
  commands/       Effect CLI and compatibility entry projections
files/materials/  schemas, layout, realization, observation and receipts
files/confext/    selection, metadata, staging and output formats
files/bootstrap/  checkout/global exposure and pre-write preparation
files/links/      retained delivery knowledge, migrated to Effect services
```

Retain useful CONFIG/Zim/LINKS behavior and Ansible rendering knowledge. Adapt
legacy scripts as described operations using the Effect process interface, with
explicit input/output and legacy exit-code translation. Effects do not reveal
undeclared side effects inside those scripts; report them as opaque.

Replace the partial flow executor, repeated filename-derived composition and
experimental string service locator. Ansible becomes one producer of module/domain
descriptors and one caller of CFR; it is not the required author of every flow.
Read-only metadata export can precede native conversion of a domain, but do not
leave two independent authorities executing the same aggregate by accident.

The next implementation checkpoint should be one real vertical slice using this
architecture: native module + generated/legacy input adapter → described confext
program → Effect services → artifact, with registry/CLI explanation from the same
objects. First review the descriptor/program seam and module delivery contract;
do not mechanically port all four scratch kernels or every domain at once.

## 11. Evidence, limits and review questions

The [four experiments](/design/compfuzor-runtime/experiments0.gpt6a.md) are evidence
for contribution kinds, placement, cross-process material reuse and bootstrap,
not Effect implementations. The additional
[Effect-native GX probe](/design/compfuzor-runtime/effect-probe0.glm53.md) tests the
public-API seam on the same checkout revision. The parent reviewed its operation
and group classes, service keys, interpreter and demo; reported demo/typecheck
results are accepted without a duplicate run.

| Evidence from the Effect probe | What it supports, and what it does not |
|---|---|
| 24 executable checks passed; strict tsgo check passed | The small source-checkout prototype runs/types correctly; not a full migration or packaged-distribution test |
| `Op` and nested `Group` are Effectable; group evaluation uses `Effect.forEach` | Direct yieldability and composition through Effect, without a separate scheduler |
| Schema-encoded description triggers no handlers, Layers, policy checks or generator bodies | Pure inspection of these CFR-owned objects; not static inference through arbitrary user implementations |
| Same observation instance yielded before and after a write runs twice | Occurrence semantics survive Effect evaluation |
| Independent modules concatenate contributed operation data under one interpreter Layer | Additive contribution is separate from provider replacement; external module discovery is still proposed |
| Denied publication fails before a link; false postcondition is typed failure; a thrown fixture error is a defect | The intended distinctions can be expressed directly in Effect; not complete execution-policy coverage |
| One Layer acquisition for several calls, fresh acquisition for separately provided runs | Construction sharing differs from operation caching; managed-runtime lifetime remains an explicit choice |
| Trying to walk a generator with fabricated observations executes author code and changes branch choice | A fake execution is not an exact static plan |

The probe leaves an unsafe generic cast in interpreter dispatch, uses direct
promise-backed I/O, and encodes descriptions without proving full decode/rebuild
round-trips. Do not copy those shortcuts into production. Domain-specific typed
handlers must preserve the input/result relationship without allowing arbitrary
`Op<A>` subclasses to claim unsupported results. The open contribution model
must not become one closed switch of every domain's operation kinds.

For example, adding a new native domain should add its definitions, schemas,
Effect service and selected Layer—not modify a global `OpKind` union or teach
the runner a new interpreter case. Generic inspection reads public descriptors;
executing a call delegates to that domain's typed interface. Schema validation
and explicit handler bindings enforce the corresponding external-data contract.

Effect's public [Effectable][effectable], [Context/Layer][layers],
[ChildProcess][child-process], [CLI][cli-example] and [Toolkit][toolkit] provide
verified source precedents. Toolkit is particularly useful as a design reference
for named schema-bearing definitions separate from handler Layers; CFR need not
depend on its AI-specific tool protocol to use that pattern.

Correct overreadings of the [earlier material scan](/design/compfuzor-runtime/effect-material0.glm53.md):
Effect values can contain opaque closures; Effectable does not reveal generator
bodies; Context/Layer is not a module-discovery or additive registration system;
durable workflow journals do not validate present filesystem state; no inference
about current stable npm releases is made from `@since` comments.

**Review still needed:** exact operation-definition/handler typing; group
contribution and override rules; whether explicit program structures are easy
enough to author; exact coverage of policy in legacy adapters; Effect module
loading/distribution; and first confext output format/compatibility policy.
These refine the Effect-native direction rather than reopening whether to use
Effect. No production dependency or runtime has been changed by this draft.

## Cross-references

- [Problem brief](/design/compfuzor-runtime/composition-problem0.gpt6a.md) — user
  direction, command specificity, open contribution and bootstrap clarification.
- [Parent experiment assessments](/design/compfuzor-runtime/experiments0.gpt6a.md)
  — why an async dispatcher alone was insufficient and what domain evidence survived.
- [Effect-native probe](/design/compfuzor-runtime/effect-probe0.glm53.md) — direct
  public-API execution evidence for Effectable descriptions and nested groups,
  plus the limits and parent-corrected source/distribution claims.
- [Experiment 3](/design/compfuzor-runtime/experiment3.sxh.md) and
  [experiment 4](/design/compfuzor-runtime/experiment4.sxh.md) — real scratch
  links/artifacts, durable evidence and the limits of those demonstrations.
- [Apply composition](/design/compfuzor-runtime/apply-flow0.glm53.md) — manual
  invocation and reusable status/verification must survive the new foundation.
- [Confext input research](/design/confext/build-inputs1.fx.md) — existing byte
  and destination sources; use this over the corrected first archaeology.
- [Earlier execution model](/design/config-anneal/execution-model0.gpt6.md) —
  attribution and deny-only multi-plane policy worth carrying forward; its fixed
  flow/indexed-file authority is not this draft's destination.

[effectable]: https://github.com/Effect-TS/effect/blob/64093976e9f595f0f9638aad5526738c78a3fa08/packages/effect/src/Effectable.ts
[child-process]: https://github.com/Effect-TS/effect/blob/64093976e9f595f0f9638aad5526738c78a3fa08/packages/effect/src/process/ChildProcess.ts#L1-L77
[config]: https://github.com/Effect-TS/effect/blob/64093976e9f595f0f9638aad5526738c78a3fa08/packages/effect/src/Config.ts#L88-L149
[context-merge]: https://github.com/Effect-TS/effect/blob/64093976e9f595f0f9638aad5526738c78a3fa08/packages/effect/src/Context.ts#L1107-L1165
[layers]: https://github.com/Effect-TS/effect/blob/64093976e9f595f0f9638aad5526738c78a3fa08/ai-docs/src/01_effect/03_services/20_layer-composition.ts
[cli-example]: https://github.com/Effect-TS/effect/blob/64093976e9f595f0f9638aad5526738c78a3fa08/ai-docs/src/70_cli/10_basics.ts
[toolkit]: https://github.com/Effect-TS/effect/blob/64093976e9f595f0f9638aad5526738c78a3fa08/packages/effect/src/ai/Toolkit.ts#L90-L108
