---
type: ArchitectureProposal
title: BINS-first workflows and native TypeScript contributions
description: A focused successor to Effect draft0 using Workflow and Activity directly, with conservative BINS admission, recursive collection and explicit domain pipelines.
resource: /design/compfuzor-runtime/effect-draft1.gpt61sol.md
tags: [runtime, effect, workflow, activity, bins, contributions, config]
status: draft
generated: { by: 'model:gpt-6.1-sol', at: '2026-09-29' }
verified: { by: 'model:gpt-6.1-sol (upstream documentation and local source inspection; proposed interfaces not implemented)' }
stale_after: 2026-10-29
sources:
  - id: predecessor
    resource: /design/compfuzor-runtime/effect-draft0.gpt6a.md
    title: Effect-native execution foundation and proposed described programs
  - id: map
    resource: /design/compfuzor-runtime/world-map0.gpt61sol.md
    title: Current-world assessment and concrete deployment examples
  - id: bins
    resource: /library/filter_plugins/bin_composers.py
    title: Current contribution ordering and aggregate construction
  - id: wrapper
    resource: /files/_bin
    title: Authored body, wrappers and child execution order
  - id: activity
    resource: https://effect.website/docs/v4/api/effect/workflow/Activity
    title: Effect rc.118 Activity contract
  - id: workflow
    resource: https://effect.website/docs/v4/api/effect/workflow/Workflow
    title: Effect rc.118 Workflow contract
  - id: operator
    title: Sep 29 clarification — BINS-first 80% admission, native TS by default, recursive aggregation, named configuration pipelines and a common module/CLI runner
---

# What changed

The [present-world map](/design/compfuzor-runtime/world-map0.gpt61sol.md) identified
fragmented composition and discovery. The operator has now supplied a more
concrete starting point:

- BINS compatibility is the first major requirement; an honest 80% starting
  place is preferable to waiting for perfect interpretation of every script.
- Workflow and Activity look like useful core concepts, not merely optional
  durable machinery bolted onto a second composition language.
- Broad build/install/config execution needs to collect its participating work,
  potentially through a semi-recursive aggregator.
- Configuration can mean a named multi-step pipeline, not only several unrelated
  `config-this` scripts. Zim and shared MCP records remain important examples.
- TypeScript executables should generally be authored/consumed as native modules.
  CFR should supply a standard export contract, common helpers, Effect CLI support
  and a main-module runner that leaves imports usable as a library.
- Do not make file/content cataloguing a prerequisite for executing useful work.

This is a focused next draft, not an accepted implementation specification. It
deliberately leaves the exact generic module typing, delivery arrangement and
engine persistence choice open. No implementation or deployment repair is made.

## 1. Central proposal: use upstream composition, add thin admission/discovery

```text
BINS adapter + native TS modules
  → selected executable contributions
  → build/install/config collecting Workflow
  → Activities and explicit child Workflows
  → Effect's process/filesystem/domain services
```

Use real upstream Workflow definitions and Activity values. Do not require new
native authors to first write CFR operation classes and then a parallel CFR
program AST. CFR supplies what upstream cannot: selected module discovery,
membership/order, explicit target binding, invocation identity, policy and CLI
admission. Domain workflows remain ordinary Effect code.

An Activity is a named Effect with result/error schemas. A Workflow adds a typed
payload and identified executions. Neither is a plugin discovery mechanism nor
a static list of future child calls. Prefer catalog descriptions and execution
traces initially; exact plans are available for explicitly collected members,
but arbitrary workflow bodies stay dynamic/opaque.

## 2. BINS admission: preserve execution before interpreting internals

### The 80% adapter

**The first compatibility unit is an explicitly admitted rendered bin, not the
unrendered shell content in its BINS recipe.** A conceptual `binActivity` binds:

- Deployment target and bin reference.
- Argument vector, including fixed bindings and explicit caller arguments.
- Invocation/occurrence identity.
- Process execution context and declared execution/exit protocol.

It returns a real Activity whose body invokes the bin through Effect's process
capability, inherits or deliberately supplies the selected process environment,
streams output, waits for exit and translates failure. This is proposed helper
behavior, not an existing CFR export.

This covers inline and template-produced shell bodies, copied scripts and other
admitted executables **without parsing their language**. Keep the existing
rendered wrapper responsible for its environment loading, `basedir`, strict mode,
guards and arbitrary shell internals. Force the selected deployment identity at
the invocation boundary rather than inheriting another deployment's `DIR`.
Do not source legacy code into the CFR process.

| Existing feature | Initial treatment |
|---|---|
| `content`, `src`, `exec`, `execs`, `early`, `late` | Render as today; execute the resulting bin opaquely |
| Environment/helpers/`basedir` | Preserve through the existing executable; do not reimplement all helpers first |
| Explicit `action`, inferred names, scope, subsystem, phase | Import existing classification/membership/order, not a new competing filename grammar |
| `compose: false` | Exclude from automatic aggregate membership; explicit invocation can still be available |
| `run`, Ansible `args`, `become`, run-bypass controls | Separate Ansible-triggered invocation policy from later manual composition |
| Ordinary exit protocol | Process completion/failure; no inference that host state now matches a declaration |
| Legacy status protocol | Explicit alternate interpretation, not globally applied to mutation bins |
| Long-running service command | Not automatically admitted to finite provisioning aggregates |
| Native-contract TS | Import and call in-process; process fallback is for unmigrated/explicit executable-only cases |

Do not silently elevate a process because a script's BINS recipe contained an
Ansible `become` field. Privileged invocation needs an explicit supported route;
unsupported cases should explain why they cannot run.

This is a coverage strategy, not a measured claim that exactly 80% of the repo
works. Coverage needs a source corpus/representative execution test later.

### Existing aggregate semantics are load-bearing

The current model is action/scope → optional subsystem → leaves. Leaves sort by
phase lane and preserve declaration order within a lane. A subsystem runs as a
contiguous group positioned at its first selected member; it is **not** a global
phase barrier. Preserve those semantics in the compatibility adapter.

An authored root such as OpenCode's `build.sh` can merge with the generated root.
[`_bin`](/files/_bin) executes its authored body before `run_all`; handling of
`late` and body-local guards depends on the wrapper shape. The authored root can
therefore already execute all contributed children.

**Never execute that complete root and separately schedule the same children.**

Use two admission shapes:

1. **Opaque executable:** one Activity runs the existing script, including any
   internal aggregation. Its declared child relationships may be browsable, but
   CFR does not also execute them.
2. **Expanded aggregate:** CFR collects and executes selected children itself.
   This is appropriate for a generated aggregate only after its wrapper context
   semantics are carried forward or shown unnecessary. Mixed authored-body plus
   children stays opaque until its body is deliberately extracted/re-authored.

Opacity is a migration boundary, not a claim that the destination is nested Bash
forever. Opaque admission gives immediate reach; the next useful migration makes
one actual aggregate native and retires its independent shell execution authority.
Compatibility scripts then invoke that same native workflow.

Shell guards can currently return zero for a bypass. Initially, record this as
an opaque successful process exit unless an explicit structured protocol reports
the skip. Do not guess skip/block outcomes by scraping human-oriented output.

## 3. A semi-recursive collector, not a universal graph

The proposed collecting Workflow asks a selected registry for the ordered members
of a named group and invokes them sequentially. Members may be Activities or
explicit child workflows/collectors. Sequential `Effect.forEach` and `yield*`
provide the execution; CFR is not a scheduler.

```text
build [selected deployment + scope]
  ├─ legacy body/leaf Activity
  ├─ native build workflow
  │    ├─ dependency Activity
  │    └─ compile Activity
  └─ subsystem collector
       ├─ native Activity
       └─ legacy Activity
```

Recursion means **declared membership**, not recursively executing every file
whose name shares a prefix. A module can contribute a complete workflow to a
group, and that workflow can collect a different explicitly named group.

The minimum collector contract is:

- Select one target/scope and explain where members came from.
- Preserve declared/legacy ordering, with sequential execution by default.
- Distinguish an opaque executable from an expanded group.
- Reject membership cycles instead of silently truncating recursion.
- Keep repeated deliberate invocations distinct from duplicate registration.
- Bind stable occurrence identity for Activities and child Workflow executions.
- Give generated/legacy collections and native modules one admission path.

Snapshot the resolved membership for an identified run so replay does not silently
select new members. This does not freeze the referenced input files. File-change
and module-version policies for resumption still need definition.

Navigation and execution need not be identical trees. Export narrow commands
explicitly; querying `config/opencode` must not itself authorize running a wider
set of consumers or switching from user to system scope.

## 4. Configuration pipelines: choose order inside a named workflow

We already have pipelines, but their composition lives inside specific runtimes:

- [`installContext`](/files/config/install.ts): copy/link publishes an existing
  canonical output; assemble mode seeds consumer inputs then assembles directly
  into the context output. Publication is not always an additional stage.
- [`installZim`](/files/zim/runtime.ts) and
  [`installActivation`](/files/zim/activation.ts): configuration, loaders, channel
  builds, startup wiring and registry publication.
- [`config-remote put`](/files/config-remote/runtime.ts): link-state mutation,
  targeted canonical assembly and rollback of that link state on assembly failure.

So the missing feature is not the notion of multi-step work. It is a common way
to **name, contribute, invoke and reuse domain-authored pipelines**.

Do not fix one universal `config = assemble → publish` pipeline. Instead:

```text
config/opencode     → selected inputs → JSON assembly → chosen exposure
config/mcp-cli      → selected inputs → client adaptation/assembly → chosen exposure
config/zim         → context preparation → assembly → cache builds → activation
config/mise        → Mise settings and Bash activation operations
```

These are proposed default workflow outlines, not a claim about current command
names or authorization to activate successor deployments. Programs may expose
narrower prepare/assemble/publish/activate entry points where useful. A broad
`config` collector selects contributed complete workflows for its explicit target;
it does not force every pipeline's assembly before every pipeline's publication.

For Zim, initially wrap the complete installer or its existing callable parts;
do not reconstruct all context machinery just to obtain workflow composition.
Re-envisioning its public prepare/build/activate interface can make the underlying
ownership model simpler later without making simplification a prerequisite.

For MCP, keep portable records inert. OpenCode and mcp-cli select/adapt the same
producer differently. Import-plus-rebuild may remain one Activity until a
deliberate refactor separates it safely; do not checkpoint inside its transaction
accidentally. Assembly does not automatically reload a live application.

## 5. Native TS module contract and a shared runner

The normal destination is a module that can be imported **and** invoked directly,
not a TS file permanently run through the process adapter.

Proposed public contents:

- Stable module identity and concise descriptions/tags.
- Exported Activity factories and/or Workflow definitions for public work.
- Handler Layers, or the explicit bindings needed to obtain them.
- Contribution membership, scope/order and command exposure declarations.
- Schema-backed input decoding for public invocation boundaries.

Do not require every private helper/Activity inside a workflow to register globally.
Activity itself has result/error schemas, not a separate parameter-schema field;
a factory binds operation inputs into its executing Effect. A module's invocation
binding or a Workflow's payload schema supplies public input decoding.

```ts
// Proposed CFR helpers/contract, not current exports or checked code.
export const cfr = defineModule({
  id: "opencode/config",
  workflows: [ConfigureOpenCode],
  layers: [ConfigureOpenCodeLive],
  contributes: [{ group: "config", workflow: ConfigureOpenCode }],
});

runIfMain(import.meta.url, () => import("./config.main.ts"));
```

The definitions and normal domain functions remain importable. `.main.ts` uses
Effect CLI and the common runner; CFR can supply a default CLI projection where
no custom frontend is needed. Both standalone and central invocation construct
the same execution context and call the same exported workflow, not two bodies.

`runIfMain` asynchronously resolves `process.argv[1]` and the module path to
physical paths before comparison, following symlinks. It dynamically imports the
CLI only when main, with a handled asynchronous continuation rather than blocking
library loading on top-level await. Importing definitions must not start the CLI,
build live deployment state or run a workflow. Trusted TS module imports are not
a sandbox; top-level implementation side effects remain an authoring concern.

Common helpers should cover the process adapter, target/context resolution,
Activity occurrence naming, collection, main detection and Effect CLI/runtime
entry. Native callers keep Effect requirements/types through their own functions;
dynamic registration must validate contracts, not erase requirements with casts.

The dependency arrangement remains a real unresolved prerequisite. Playbooks can
deliver source plus target-specific data, rather than bake every target into code,
but deployed modules need a supported way to resolve the shared CFR/Effect
packages. Choose a managed package root, bundling contract or equivalent before
calling native module delivery solved. Built-in and selected repository-local
modules should use the same export shape, not separate authoring systems.

## 6. What files/templates need from this model

File/content declarations do not have to become executable entries. Keep them
as recipe inputs, generated specs or materials referenced by workflows. A file
becomes executable work only through an admitted operation such as render,
assemble, copy, publish or compile.

If a template produces a bin, the BINS adapter executes the resulting bin. If a
template produces JSON, the consumer's workflow processes that JSON. Neither
case requires a catalog of every file before useful execution can begin.

Retain existing attribution/resources where useful for queries. Richer material
inventory can support later confext and placement work without being compulsory
for this BINS-first composition slice.

## 7. Workflow semantics to settle without derailing the first slice

The linked upstream docs and installed source both describe rc.118. Use their
actual Workflow/Activity APIs rather than older Effect Service/CLI examples.

- Ordinary explicit runs get fresh execution identity. Resume addresses an
  identified run; deployment identity alone is not its idempotency key.
- Name Activity occurrences and child workflow executions using their role/target
  in that run. Repeated work must not accidentally reuse one Activity result.
- Default process adapters must not opt legacy mutations into automatic retry
  unnoticed. Activity's default interruption retry behavior needs deliberate
  configuration; failure/interruption translation is part of the adapter contract.
- Opaque scripts can partially mutate before failure. Replay/resume is not
  exactly-once execution and must not promise automatic rollback.
- Start with an explicit engine-lifetime choice. Memory is valid for local fresh
  execution but not durable resumption across processes. Persistent execution is
  a separately specified capability, not a reason to require a daemon immediately.
- Keep fresh live status available; replayed completion describes run history.

## 8. Proposed architectural checkpoint

The next checkpoint should show one real mixed aggregate, preferably OpenCode
build because its authored body plus contributed children tests compatibility,
and a compact native configuration workflow. Zim and two MCP consumers test that
the module contract admits richer pipelines without universally cataloguing files.

The checkpoint must explain:

1. Which BINS records are admitted and which are opaque/expanded/unsupported.
2. How broad and narrow execution select and order the same contributions.
3. What one native module exports and how both main and imported execution work.
4. How native and legacy work mix without running either twice.
5. What shell composition can actually be retired, and what remains temporarily.

Before implementation, review the opaque/expanded aggregate boundary, public
module/export typing, dependency delivery and fresh-run/replay policy. Do not
require a complete universal plan graph or a new CONFIG ownership model first.

## Cross-references

- [Effect draft0](/design/compfuzor-runtime/effect-draft0.gpt6a.md) — retained
  execution/domain division; this draft changes its default authored composition
  direction toward upstream Workflow/Activity instead of a required CFR AST.
- [Present-world map](/design/compfuzor-runtime/world-map0.gpt61sol.md) — source
  context for the deployment examples and unresolved loading/discovery work.
- [Bin composition documentation](/doc/bins.md) and
  [BINS merge behavior](/doc/subsys.md#bins-merge-behavior) — root/body composition,
  membership and wrapper contracts; current source includes the newer config lane.
- [CONFIG consumer toolkit](/doc/config/consumer-toolkit.md) — existing assembly,
  input and publication semantics, including differences between MCP consumers.
- [Composition problem brief](/design/compfuzor-runtime/composition-problem0.gpt6a.md)
  — navigable specificity, multi-home contribution and explicit-target concerns;
  aggregation must answer these without becoming a speculative global graph.
