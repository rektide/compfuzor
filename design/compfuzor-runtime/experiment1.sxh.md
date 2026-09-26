---
type: ArchitectureExperiment
title: CFR backbone experiment 1 — capabilities, consumer programs, CLI as lens
description: Executed throwaway probe testing whether contributed callable capabilities and consumer-authored programs can replace a route/action/flow-centered core.
resource: /design/compfuzor-runtime/experiment1.sxh.md
tags: [compfuzor, runtime, composition, capabilities, programs, experiment]
status: draft
generated: { by: 'model:openai/gpt-6-sol#xhigh', at: '2026-09-26' }
verified: { by: 'model:openai/gpt-6-sol#xhigh', at: '2026-09-26' }
sources:
  - id: experiment-plan
    resource: /design/compfuzor-runtime/experiments0.gpt6a.md
    title: Sequential experiment assignment and architectural checkpoint
  - id: problem
    resource: /design/compfuzor-runtime/composition-problem0.gpt6a.md
    title: Operator corrections and composition tests
  - id: probe
    resource: /.test-agent/cfr-backbone/experiment1/README.md
    title: Throwaway executable probe; scratch is ignored
---

# CFR backbone experiment 1: capabilities, consumer programs, CLI as lens

## Question and scope

The existing BINS compositor assembles shell `run_all` wrappers and a separate
catalog infers partial runtime flows from their names. The operator asks to
reinterpret the **library and runner**, not merely emit generalized wrappers.
Can independent TS modules and scripts offer functionality, while **consumers
author programs over those offers**, and `apply/network/extra-addr` versus
`apply/network` become selections of one program instead of a permanent route
tree or an action's declared memberships? Which complexity reappears when this
is actually run?

This is a deliberately independent new kernel in ignored
[`experiment1/`](/.test-agent/cfr-backbone/experiment1/README.md), not a
production change, migration, confext build, runtime install, or new contract.
All mutations are **mock writes to one scratch JSON fixture**. No Ansible,
systemd, links delivery, networking, host config, project storage, or bootstrap
was exercised. `cf-r` is an *idea* for a normal checkout's runtime to install
itself globally; it is not a found executable. Its bootstrap path belongs to
the separate `compfuzor-runtime-bootstrap` ticket, not this experiment.

## Two different possible centers

1. **Callable offers + authored consumer programs (probed).** Providers publish
   callable capabilities with an independent identity, subject, contract, and
   source. A consumer explicitly admits sources for each required contract,
   selects subjects, and authors an operation that combines those capabilities.
   The runner executes the resulting program. Programs themselves can be
   reused. Paths are one presentation-layer mapping from operator spelling to
   `(program, subject selection)`. This can admit TS and descriptor-backed
   scripts at runtime without handing composition authority to Ansible or a
   fixed global set of flows.
2. **Desired-state products + interpreters (not probed).** Contributors publish
   state descriptions; independent consumers interpret selected descriptions
   as build, apply, status, or artifact projections. This could provide a deeper
   shared backbone for rendered materials and confext than calls to opaque
   scripts. But current imperative apply bins, ad hoc status commands, and
   lifecycle preparation cannot truthfully be made state descriptions without
   choosing domain-specific interpreters and observation protocols first. Doing
   that in experiment 1 would make the toy look elegant by excluding today's
   actual contributions. Preserve it as a live alternative for the placement
   and confext probe, not a universal framework to predeclare now.

Neither alternative implies that a universal action/route graph is necessary.
The first is also more than renamed actions: **the unit of selection is a
contractually offered capability for a subject**, whereas a consumer owns the
program, source acceptance, ordering, and relation to other programs. No offer
asserts `joins: apply/network`, no tag auto-enrolls it, and no filename becomes
the operation's identity.

## Exact interfaces actually exercised

The probe's small API lives in [`kernel/contracts.ts`](/.test-agent/cfr-backbone/experiment1/kernel/contracts.ts),
[`kernel/library.ts`](/.test-agent/cfr-backbone/experiment1/kernel/library.ts),
and [`kernel/runner.ts`](/.test-agent/cfr-backbone/experiment1/kernel/runner.ts).
These are illustrative code, not proposed final schemas:

```ts
type OfferInfo = {
  id: string; source: string; contract: string; subject: string;
  tags: string[]; description: string;
};
type Offer = OfferInfo & { handler:
  | { kind: "module"; run(input: Input): Promise<Result> }
  | { kind: "script"; file: string };
};
type Program = {
  consumer: string; query: string;
  stages: { name: string; calls: { offer: string; subject: string; why: string }[] }[];
};

library.add(...builtinOffers, ...projectOffers);
await library.addDescriptor("sources/extra-addr.json");
const p = apply(library, "network/extra-addr");
library.explain(p);                    // no handler calls
await execute(library, p, fixture);   // explicit manual invocation only
```

Three genuinely independent source shapes run: bundled-like TS
[`sources/builtin.ts`](/.test-agent/cfr-backbone/experiment1/sources/builtin.ts)
observes static-only, project TS
[`sources/project.ts`](/.test-agent/cfr-backbone/experiment1/sources/project.ts)
changes two fixture subjects, and a JSON descriptor
[`sources/extra-addr.json`](/.test-agent/cfr-backbone/experiment1/sources/extra-addr.json)
provides a script handler
[`sources/extra-addr-status.ts`](/.test-agent/cfr-backbone/experiment1/sources/extra-addr-status.ts).
The script receives a serialized inventory on stdin and queries its own
subject's `iface.change/v1` peers; its stdout is a JSON result. Thus scripts
can participate and inspect capabilities without importing the library or
having an installed global `cfr`. A standalone script-to-runner query command,
reverse index of *which programs consume an offer*, and long-lived protocol
remain unproven.

The operator-facing program is authored separately from its providers:
[`consumers/apply.ts`](/.test-agent/cfr-backbone/experiment1/consumers/apply.ts)
imports and reuses the **program** exported by
[`consumers/status.ts`](/.test-agent/cfr-backbone/experiment1/consumers/status.ts).
Acceptance is consumer-side
[`consumers/selection.ts`](/.test-agent/cfr-backbone/experiment1/consumers/selection.ts):

```ts
const sources = {
  "iface.change/v1": ["project.iface"],
  "iface.observe/v1": ["builtin.network", "script.iface"],
} as const;

export function apply(library: Library, prefix: string): Program {
  const subjects = selected(library, prefix, "iface.change/v1");
  const related = status(library, prefix, subjects); // reuse another consumer
  return {
    consumer: "consumer.network.apply", query: prefix,
    stages: [
      { name: "change", calls: calls(library, subjects, "iface.change/v1", "explicit consumer acceptance") },
      ...related.stages.map((stage) => ({ ...stage, name: "related-status" })),
    ],
  };
}
```

[`views/cli.ts`](/.test-agent/cfr-backbone/experiment1/views/cli.ts)
projects `apply/network/extra-addr` to `apply(library,
"network/extra-addr")`, `apply/network` to `apply(library, "network")`,
and `status/network` to `status(library, "network")`. Even `apply` itself
maps to the consumer's default network selection. Segment-prefix comparison
is literal; it does not parse hyphens. There is no directory/file collision
for both `apply/network` and `apply/network/extra-addr` because neither is a
physical command file. A future CLI could instead expose `cfr apply
--subject network/extra-addr`; the library does not care.

## Reproduction and selected output

From the repository root (Node 26, no new packages):

```sh
node .test-agent/cfr-backbone/experiment1/demo.ts
# optional type check, existing dev tool only:
pnpm exec tsgo --ignoreConfig --noEmit --target esnext --module nodenext \
  --moduleResolution nodenext --allowImportingTsExtensions --types node \
  .test-agent/cfr-backbone/experiment1/demo.ts \
  .test-agent/cfr-backbone/experiment1/sources/extra-addr-status.ts
```

Both commands passed. The full demo prints inventory, narrow/broad/status
plans with offer ID/source/contract/handler/tags/selection reason, every
executed result, fixture state, and negative cases. A captured run resides
in ignored `experiment1/scratch/demo-output.txt`. Representative output:

```text
ASSERT removing final component selects same broad consumer program: PASS
== fixture after ALL planning (no execution) ==
{ "network/static-only": false, "network/extra-addr": false }
ASSERT planning has zero effects: PASS
== direct status before any apply ==
... script.iface.extra-addr.observe ...
    "observed": { "present": false,
                  "changePeers": ["project.iface.extra-addr.change"] }
== explicit narrow apply + related status ==
  change project.iface.extra-addr.change
  related-status script.iface.extra-addr.observe (present: true)
== fixture after narrow ==
{ "network/static-only": false, "network/extra-addr": true }
ASSERT narrow only touches selected subject: PASS
== explicit broad apply + related status ==
  change project.iface.extra-addr.change
  change project.iface.static-only.change
  related-status script.iface.extra-addr.observe
  related-status builtin.network.static-observe
== final fixture (mock state ONLY) ==
{ "network/static-only": true, "network/extra-addr": true }
ASSERT unknown subject refuses invocation: PASS
ASSERT unaccepted source cannot enlarge or break consumer selection: PASS
Error: iface.change/v1 for network/extra-addr: expected one offer from
  [project.iface], found [project.iface.extra-addr.change,
  project.iface.competing-change]
ASSERT ambiguous trusted providers fail closed: PASS
```

The trace above is shortened for readability, not a verbatim substitute for
the demo's full JSON. The static-only and extra-addr fixture subjects borrow
the names of the two iface playbooks, but neither playbook is executed.

## Surprises, costs, and falsification

- **Subject admission is not free.** The initial implementation enumerated
  subjects from *every* offer, then resolved each required contract from
  approved sources. A foreign unapproved contribution could add
  `network/unsolicited` and make `apply/network` fail for missing approval.
  The final implementation derives an operation's subject set from its
  **driving contract and approved sources**. Apply drives from changes;
  independent status drives from observations; apply's related status uses
  apply's subject set rather than silently enrolling all status-only subjects.
  An unapproved contribution now cannot expand or break a broad apply plan.
- **Trust in a source does not imply uniqueness.** Two change providers for one
  subject/contract from an accepted source must not be selected by load order;
  `Library.require()` rejects ambiguity. Later we may need consumer-specific
  choice/priority or multiple deliberate invocations. This experiment does not
  invent that policy.
- **Authoring cost moved, not vanished.** No join for every route, but a
  consumer must know the *contract*, accepted *source identities*, whether to
  drive selection from change or observation, and what relationship/status
  semantics it wants. Each provider must know the same *subject identifier*.
  These are coupling points. A different observer subject, fan-out status,
  cross-domain prerequisites, conditional verification, or several scopes
  needs authored mapping/composition beyond the current equality join.
- **A program is not a shell wrapper.** A source has no entry-point position;
  a program can reuse another program (`apply` consumes `status`) and can
  expose a plan without executing its offers. The `Stage[]` structure is just
  this consumer's choice of order, not a universal lifecycle or phase schema.
  Another consumer can choose different order or result interpretation without
  changing source registrations. The library handles source discovery,
  ambiguity, selection, inspection, and dispatch; the runner only runs a
  *selected* program. This makes it a backbone, not a renamed scheduler.
- **Result semantics are presently inadequate.** `ok: true` on observation
  means the reporter ran, not that `present: false` satisfies a postcondition.
  `apply` currently runs all selected changes, then related status; a failed
  change stops all subsequent calls. There is no per-subject verification gate,
  retry, idempotence proof, typed drift outcome, bypass, dry-run guarantee,
  rollback, effect confinement, or confirmation of disruptive operations.
  Only explicit `execute()` prevents accidental apply in this toy.
- **The loaded library is mutable.** Plans retain offer IDs but execution looks
  them up again; a changed/late module could change an already-inspected
  program. Need snapshot identity or immutable binding before calling this a
  safe executor. TS module imports also execute top-level code even when we
  only ask to inspect; `planning has zero effects` in this demo speaks only to
  handlers in these cooperative fixtures. A JSON descriptor avoids that
  particular import-time risk but its script still has unrestricted process
  rights here. Do not treat this as a sandbox or production trust policy.
- **Not yet an answer for project material.** No byte provenance, publication
  intent, confext packaging, pre-write preparation, deployment/scope target,
  legacy BINS mapping, or bootstrap appears in this probe. Offering an opaque
  `build-confext` handler would just conceal those unsolved relationships.

## Architectural checkpoint / next question for parent assessment

The experiment **supports** a smaller core than an action registry plus
route-join compiler plus fixed flow scheduler: an offer inventory by contract
and subject, consumer-authored programs assembled as data, and an executor of
explicitly selected calls. The CLI hierarchy can be one view. The most
consequential finding is **where authority must live**: consumer approval
determines not just who runs but which subjects even enter a broad operation;
source contributions should be discoverable without automatically becoming
authorized execution. Program reuse is real, not another status action cloned
into an apply membership.

The next highest-yield question, **subject to parent revision before experiment
2**, is whether this consumer-side boundary survives multiple independent
consumers, late offers, ambiguous providers, distinct observation subjects,
and repeated invocations—*without* devolving into a hidden central registry of
joins or sacrificing an immutable, explainable plan. Try to break source-level
acceptance and equality-on-subject under those pressures before expanding into
layout or confext. The parent should decide whether this is the right next
probe; none of it was implemented here.

## Cross-references

- [Problem and operator corrections](/design/compfuzor-runtime/composition-problem0.gpt6a.md)
  — hard requirements versus unconfirmed phase/registry hypotheses, and the
  separate clarification of the `cf-r` bootstrap idea.
- [Sequential experiment brief](/design/compfuzor-runtime/experiments0.gpt6a.md)
  — experiment-1 boundary, parent checkpoint, and why the next experiment is
  not automatically authorized by this report.
- [Sol composition draft](/design/compfuzor-runtime/composition-draft1.sxh.md)
  — the earlier route-join design; this probe rejects its *route placements as
  core* while preserving its useful path-as-query and independently reusable
  invocation observations.
- [GX composition draft](/design/compfuzor-runtime/composition-draft1.glm53.md)
  — one-description/many-projections and companion insight, but not its
  single-Ansible-writer, data-only deployments, or narrow/broad execution
  policy split.
- [Parent draft](/design/compfuzor-runtime/composition-draft0.gpt6a.md)
  — explicit memberships and reusable operations; the experiment tests
  consumer programs without declaring membership records on every offer.
- [Apply investigation](/design/compfuzor-runtime/apply-flow0.glm53.md)
  — manual apply and a status relation are real needs, not evidence that a
  fixed fourth flow or shell wrapper is the right backbone.
- [Confext inputs](/design/confext/build-inputs1.fx.md)
  — byte/destination and mode evidence for a *later* material projection
  experiment; absent from this mock and not validated by it.
- [Earlier execution model](/design/config-anneal/execution-model0.gpt6.md)
  — contributor/action/invocation and distinct execution planes; typed
  outcomes and policy remain important debts rather than claims of this toy.
