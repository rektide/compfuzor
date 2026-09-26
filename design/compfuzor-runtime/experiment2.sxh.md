---
type: ArchitectureExperiment
title: CFR backbone experiment 2 — choose implementations, collect work, contribute programs
description: Executed probe separating provider choice from additive contributions, with independently registered programs, pinned planning, postcondition interpretation, and material/order counterexamples.
resource: /design/compfuzor-runtime/experiment2.sxh.md
tags: [compfuzor, runtime, composition, programs, material, experiment]
status: draft
generated: { by: 'model:openai/gpt-6-sol#xhigh', at: '2026-09-26' }
verified: { by: 'model:openai/gpt-6-sol#xhigh', at: '2026-09-26' }
sources:
  - id: parent-checkpoint
    resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Experiment-1 assessment and experiment-2 question
  - id: predecessor
    resource: /design/compfuzor-runtime/experiment1.sxh.md
    title: Capability and consumer-program probe
  - id: executable-probe
    resource: /.test-agent/cfr-backbone/experiment2/README.md
    title: Experiment-2 executable scratch and usage
---

# CFR backbone experiment 2: choosing is not collecting

## Problem and hypothesis

[The parent checkpoint](/design/compfuzor-runtime/experiments0.gpt6a.md#experiment-1--parent-assessment)
accepted experiment 1's provider/consumer/CLI separation but rejected its
`require exactly one` and hard-coded source list as the answer to broad, easy
contribution. Question: can **many independent modules add intended work to
one operation/subject without consumer edits**, while a consumer still chooses
its contribution set, programs themselves can be contributed and composed,
and a plan stays explainable after more modules appear?

This is an executable, deliberately limited alternative kernel under ignored
[`experiment2/`](/.test-agent/cfr-backbone/experiment2/README.md). Experiment
1 was preserved. This work touched no production runtime, Ansible, real
project material, network configuration, host services, or systemd extensions.
Every effect is a **scratch mock**.

## Two genuinely different moves

1. **Open topic subscription.** Any loaded module emitting a matching
   `network.configure/v1` entry is automatically collected by any program
   subscribing to that topic. This is maximally easy for contributors and
   avoids source lists, but a load-path change implicitly changes *every*
   matching run, and a consumer has no stable notion of its selected set. A
   globally registered program name also risks accidentally capturing an
   unexpected extension. A topic alone does not answer selection authority.
2. **Scoped contribution set + independent provider bindings (probed).** A
   caller explicitly names a **scope** of modules. A consumer program says
   `collect(channel, subjects)` and sees all matching entries in that scope;
   it does not name source modules or require one entry per subject. The scope
   separately **binds one implementation** of a substitutable contract (here,
   script transport). Programs are themselves independently contributed
   records, discovered by ID and selected within the same scope. Extending
   the scope is the intentional one-place enrollment change; no consumer or
   kernel edit is necessary. The cost is that there must be a real scope
   author/loader and a public rendezvous contract (`channel`)—implicit
   membership has not magically disappeared.

A third route would put every entry ID in an explicit operation manifest. It
would pin cleanly but turns a new useful module into a manifest edit per
operation and makes nested reuse harder. The scoped set is the more
illuminating compromise to run, **not a security provenance system**. A module
ID is a locally assigned label; the demo does not authenticate modules.

## Exact authored surfaces

The probe separates three different things in
[`kernel/types.ts`](/.test-agent/cfr-backbone/experiment2/kernel/types.ts):

```ts
type ContributionModule = {
  id: string;
  entries?: Entry[];       // additive work on a channel + subject
  programs?: Program[];    // independently discoverable consumers
  transports?: Transport[]; // alternatives; choose exactly one by binding
};
type Scope = {
  id: string;
  modules: string[];       // selected contribution set
  bind: { "script.transport/v1": string }; // chosen provider ID
};
type Program = { id: string; description: string; build(query: Query): Recipe };
type Recipe =
  | { kind: "series"; parts: Recipe[] }
  | { kind: "collect"; channel: string; prefixes: string[];
      interpret: "none" | "report" | "require-ready" }
  | { kind: "use"; program: string; query: Query; again?: boolean };
```

The independent TS modules
[`modules/iface.ts`](/.test-agent/cfr-backbone/experiment2/modules/iface.ts)
and [`modules/route.ts`](/.test-agent/cfr-backbone/experiment2/modules/route.ts)
both add executable `network.configure/v1` entries for **the same subject**,
`network/extra-addr`: mock address and mock default route. Their IDs sort as
`10.iface.address` then `20.route.default`. An independent late
[`modules/dns.ts`](/.test-agent/cfr-backbone/experiment2/modules/dns.ts)
adds `30.dns.extra` to that very same collection. The
[`modules/extra-observer.json`](/.test-agent/cfr-backbone/experiment2/modules/extra-observer.json)
descriptor contributes a script observer; its
[`extra-observer.ts`](/.test-agent/cfr-backbone/experiment2/modules/extra-observer.ts)
receives the selected inventory and reports both readiness and its peer
configuration entries. Another TS observer reports the static-only subject.
There is no Ansible-only writer and no restriction to data-only deployments.

Two unrelated TS modules contribute the programs themselves:

```ts
// programs/status.ts — separately registered, discoverable as network.status
build(query) {
  return collect("network.observe/v1", query.prefixes,
    query.mode === "verify" ? "require-ready" : "report");
}

// programs/apply.ts — refers to status by PROGRAM ID, no status-module import
build(query) {
  return series(
    collect("network.configure/v1", query.prefixes, "none"),
    use("network.status", { prefixes: query.prefixes, mode: "verify" }),
  );
}
```

See [`programs/status.ts`](/.test-agent/cfr-backbone/experiment2/programs/status.ts)
and [`programs/apply.ts`](/.test-agent/cfr-backbone/experiment2/programs/apply.ts).
The third contributed [`programs/watch.ts`](/.test-agent/cfr-backbone/experiment2/programs/watch.ts)
references status twice ordinarily and once with `again: true` to test whether
set-like selection can be distinguished from an intentional new occurrence.
All three programs appear in `Inventory.describe()` with ID, source module,
and purpose. [`views/path.ts`](/.test-agent/cfr-backbone/experiment2/views/path.ts)
optionally maps `apply/network/extra-addr` and `apply/network` to one program
with different subject prefixes; the kernel addresses programs by ID and
query, **not by CLI path**.

The [catalog](/.test-agent/cfr-backbone/experiment2/kernel/catalog.ts)
loads a scope's module set and resolves the one `script.transport/v1` binding
to either `runtime.node` or the deliberately rejecting `runtime.disabled`.
All matching `network.configure/v1` entries remain independent and additive;
switching the transport changes how the script runs, not the number of work
entries. This distinction is the point of the experiment, not a proposal to
make process launching the only pluggable CFR capability.

## Planning versus execution, multiplicity, stability

[`compile()`](/.test-agent/cfr-backbone/experiment2/kernel/plan.ts) executes
trusted program **builders** at planning time, selects matching entries by
segment prefix, snapshots their identities/handlers and the selected transport,
and expands nested program references into a printable tree. It does **not**
invoke entry handlers. [`execute()`](/.test-agent/cfr-backbone/experiment2/kernel/run.ts)
walks only that tree, with a captured inventory passed to scripts; it does not
re-query the mutable catalog. `scope.modules` makes a freshly compiled
`pinned-base` plan exclude DNS even after the registry learns about DNS;
`extended` explicitly includes it. A previously compiled plan also excludes
DNS when run *after* registration. This is **registry-extension stability**,
not reproducible code bytes or sandboxing: module top-level code and program
builders are trusted, captured TS closures can have mutable state, and a
script file can change at its captured path between plan and execution.

A collection unions overlapping subject prefixes by entry ID (`network` plus
`network/extra-addr` selects the latter's entry once). Reusing the same
program ID with the same query in a nested plan defaults to a `reuse` marker,
not another call; `again: true` creates another actual occurrence. These are
explicit *toy semantics*: `seen` is keyed by program/query serialization;
different query spellings with equivalent sets are not canonicalized. The
relative ordering of default and repeated uses matters. A fuller runtime
must negotiate repeated observations and multi-role reuse, not silently claim
global deduplication is always correct.

An observer's process success is separate from its observation:
`{completed:true, observation:{ready:false}}`. Direct status interprets it as
`attention` (report mode); `apply` uses the same program in verification mode
and returns `failed` with `postcondition false`. This is a genuine execution
result difference, not just a printed plan. The `ready` boolean is intentionally
domain-specific and provisional; no general result schema, bypass policy, or
transaction model is established.

## Executed evidence

From the repo root (Node 26, no new dependencies):

```sh
node .test-agent/cfr-backbone/experiment2/demo.ts
# optional verification using the existing dev tool:
pnpm exec tsgo --ignoreConfig --noEmit --target esnext --module nodenext \
  --moduleResolution nodenext --allowImportingTsExtensions --types node \
  .test-agent/cfr-backbone/experiment2/demo.ts \
  .test-agent/cfr-backbone/experiment2/modules/extra-observer.ts
```

Both commands passed. The complete output, including full inventories, plans,
results, and fixture state, is in ignored
`experiment2/scratch/demo-output.txt` and is reproduced by the first command.
These are shortened excerpts with the exact relevant IDs and outcomes:

```text
== baseline plan (two independent modules change same subject) ==
network.apply:
  network.configure/v1: 10.iface.address, 20.route.default
  network.status -> network.observe/v1: observe.extra-addr
ASSERT collector retains both additive entries and nested observer: PASS
ASSERT planning did not execute mutation: PASS

== extended plan: same apply program, DNS included by scope ==
network.configure/v1: 10.iface.address, 20.route.default, 30.dns.extra
ASSERT previous plan and fresh pinned-scope plan exclude late module: PASS
ASSERT new contribution joins both extended narrow and broad selections without consumer changes: PASS
ASSERT old plan did not dynamically acquire DNS: PASS
ASSERT script queried pinned plan inventory, not newly registered contributions: PASS
ASSERT script observes newly included contribution via extended inventory: PASS

== extended apply: all change handlers succeed but observer reports false ==
10.iface.address: completed
20.route.default: completed
30.dns.extra: completed
observe.extra-addr: failed, "postcondition false: ... forcedNotReady=true", observedReady: false
ASSERT apply fails verification when successful observer returns ready=false: PASS
== same contributed status program in direct report mode ==
observe.extra-addr: attention, observedReady: false
ASSERT direct status reports drift without masquerading as invocation failure: PASS
ASSERT satisfied postcondition completes: PASS

== watch trace (reused selection versus actual repeated call) ==
observe.extra-addr: completed
network.status: reused (same program/query)
observe.extra-addr: completed (explicit again)
ASSERT explicit again creates second occurrence; duplicate selection does not: PASS
```

The alternate transport was also chosen in a second scope: its invocation
failed while the selected status entry remained `observe.extra-addr`. None of
these effects targeted a host path; the script and TS steps read/write only
`experiment2/scratch/mock-network.json` and the isolated
`experiment2/scratch/mock-order.json` counterexample fixture.

## Falsification, unresolved tensions, and what changed

**Counterexample 1: collecting is not resolving ownership.** The independent
[`modules/conflict.ts`](/.test-agent/cfr-backbone/experiment2/modules/conflict.ts)
declares another address writer at the same `claim:
"network/extra-addr/address"`. Extending the scope gives:

```text
Error: claim collision network/extra-addr/address: 10.iface.address and
40.iface.other-address; additive collection cannot choose a winner
ASSERT collision is refused at planning time, not silently last-writer-wins: PASS
```

This is a *declared* claim and an intentionally shallow collision check within
one collection. Real destination conflicts can arise across channels, layouts,
symlinks and differing target paths; opaque handlers can collide without
declaring any claim. The generic kernel cannot decide if two records should
append, override, merge, fan out, or be rejected. Domain-specific material
ownership and projections cannot be replaced by a bag of executable actions.

**Counterexample 2: deterministic sorting is not dependency order.** A second
run puts otherwise identical route work under entry ID `05.route.early`.
Lexical sorting puts it before `10.iface.address`; the mocked route handler
refuses to proceed without the address. The plan is inspectable but wrong:

```text
== ordered by ID, route runs first and refuses missing address ==
{ "outcome":"failed", "events":[{"id":"05.route.early",
  "event":"failed", "detail":"MOCK route requires address first"}] }
ASSERT simple collection order does not encode causal prerequisites: PASS
```

Adding global phases or an unrestricted dependency graph merely to rescue this
toy would prejudge which dependencies are local to a domain operation and which
cross independent owners. We need a concrete material/lifecycle example to
decide that seam; at minimum, `id` order must not masquerade as semantics.

**Revising experiment 1.** Its `require exactly one` was appropriate for
choosing a provider, **wrong** for collecting work; the hard-coded list of
acceptable source names need not live in each consumer. Caller-selected
scopes allow new modules to contribute to existing programs without consumer
edits. The scope still changes deliberately, so this is *open contribution
within a selected set*, not automatic enrollment from arbitrary files. The
common channel is an intentional rendezvous/membership contract, not a claim
that composition needs no declarations. Programs as discoverable, independently
registered contributions are practical; a nested `use("network.status")`
survives a separate implementation module and returns different status/verify
outcomes. What experiment 1 got right—CLI as projection and consumer-owned
composition—survives in this bounded example.

**Costs not solved:** a stable public channel name, subject compatibility,
program interface/version negotiation, scope authoring and loading, how to
explain attribution across compiled/overridden contributions, optional or
missing status, cross-program repeated work, true provider binding for more
than the script transport, immutable artifact/code identity, script inspection
outside invocation, multi-deployment and system/user scope, concern bypasses,
concurrency, and no mutation at import/plan time. The CLI view's three program
aliases are still written by hand; dynamically surfacing new programs in the
CLI requires separate view policy. The exercise neither certifies scripts
safe nor assumes module ID labels authenticate them.

## Architectural checkpoint and next highest-yield question

Experiment 2 supports a sharper library shape: **a selected contribution set,
one binding for each substitutable service, many collected entries per domain
channel, and independently discoverable programs that compose by ID**. A
program is an author of selection, order, reuse and result interpretation; a
runner binds and executes its frozen *chosen* expansion. That is stronger than
putting more handlers under a scheduler: it shows exactly where new work can
enter and where one implementation is required. But claim collision and
ordering failures show that an operation is not universally a sorted multiset
of calls.

For parent assessment before any next authorization: the highest-yield next
question toward actual material/layout/confext reasoning is **what may be
collected as an artifact/material description and how ownership, destination
exposure, and dependency order are decided before choosing a physical layout**.
Compare existing `/etc/opt` delivery and project-contained layout plus a
build-only confext projection using *the same declared material*; confront
conflicting destinations, file modes, symlink direction, and independent
build/publication outcomes rather than adding an opaque `confext.build` call.
Do not infer experiment 3 is authorized or this toy's channels are accepted.

## Cross-references

- [Experiment-1 report](/design/compfuzor-runtime/experiment1.sxh.md) — the
  exact-one and fixed-source constraints revised here; its previous probe is
  preserved in the adjacent ignored directory.
- [Parent checkpoint](/design/compfuzor-runtime/experiments0.gpt6a.md#experiment-1--parent-assessment)
  — states the choose-versus-collect question and bounded experiment order.
- [Original composition problem](/design/compfuzor-runtime/composition-problem0.gpt6a.md)
  — broader project/runtime aspirations and execution controls not claimed by
  this fixture exercise.
- [Confext inputs](/design/confext/build-inputs1.fx.md) — real iface material,
  destination, permissions and build-only constraints needed for the proposed
  next probe, **not** evidence that these mock entries deliver a confext.
- [Earlier execution model](/design/config-anneal/execution-model0.gpt6.md)
  — existing invocation/flow/policy vocabulary; typed outcomes and distinct
  execution planes remain debts for any proposed backbone.
