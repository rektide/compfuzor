---
type: ExperimentPlan
title: Four sequential probes of a reinterpreted CFR backbone
description: Parent-led architectural experiments on the runtime library and runner, not incremental generalization of gen_bins.
resource: /design/compfuzor-runtime/experiments0.gpt6a.md
status: draft
generated: { by: 'model:gpt-6-astra', at: '2026-09-26' }
sources:
  - id: operator
    resource: cotail://ses_f2198adecffeZm5gWy0G9BCV3h
    title: quiet-tiger — four sequential Sol experiments with parent assessment
---

# Four experiments, with architectural checkpoints

The operator corrected the emphasis: this work is about reinterpreting the
**CFR library and runner backbone**, not merely generalizing BINS. The current
runtime feels constrained, limited, and weird. Bold replacement is welcome.
The operator is dubious that many experiments are the best route but authorizes
four high-yield experiments in sequence: Sol investigates/prototypes, the parent
reads and assesses, optionally iterates with Sol, then chooses the next probe.

## Method

- Use Sol xhigh sequentially. No dependent experiment launches before parent
  assessment of the preceding one. Follow-ups within an experiment are welcome.
- Prototypes are throwaway TypeScript in `.test-agent/cfr-backbone/`, with a
  README and a one-command demo. No production changes, host installation,
  networking changes, storage migration, or extension activation.
- Each experiment needs a falsifiable architectural question, concrete authored
  examples and observable behavior, and a durable report of surprises, costs,
  rejected approaches, and what should change in our understanding.
- Preserve coherent reports as separate explicit-path commits. Scratch code is
  not production; record enough interface examples and demo evidence in reports
  that conclusions do not depend on an untracked implementation alone.
- Review meaningful interfaces and actual behavior, not just success claims.
  Do not mistake fixtures or mocked effects for demonstrated integration.
- Treat existing drafts as competing hypotheses, not an accepted specification.

## Initial trajectory, revisable after each checkpoint

1. **Reinterpret the core.** What is the smallest powerful library/runner model
   in which independent modules and scripts contribute, consumers compose, and
   CLI narrowing is a view of that model—not the architecture itself? Challenge
   the registry/action/route framing if something better emerges. No Ansible
   dependency in the experimental core.
2. **Composition under pressure.** Attack the emerging model with multiple
   consumers, late contributions, nested composition and order/policy tensions.
   The exact counterexample is selected after experiment 1.
3. **One project, several physical realizations.** Test real material/link
   relationships, opposing layouts, and confext build projection against the
   revised core. Avoid simply blessing a renamed containered profile.
4. **Bootstrap and end-to-end explanatory power.** Ask whether the resulting
   model can support checkout-local self-installation, early preparation, and
   a representative build without separate ad hoc machinery. Use only isolated
   roots and fixtures. Select the final challenge from prior failures, not from
   a predetermined implementation checklist.

These are hypotheses about the highest-yield sequence, not four frozen feature
specifications. A surprising first result should change subsequent questions.

## Context

- [Problem brief](/design/compfuzor-runtime/composition-problem0.gpt6a.md): user
  direction and bootstrap clarification; framing is not mandatory.
- [Sol draft](/design/compfuzor-runtime/composition-draft1.sxh.md): route joins,
  selection rather than wrappers, and phase barriers; critique its closed project
  contribution sources and its rejection of self-bootstrap.
- [GX draft](/design/compfuzor-runtime/composition-draft1.glm53.md): one description,
  many projections and related-operation metadata; critique sole Ansible authority,
  restricted TS contribution, and changing semantics for narrow versus broad runs.
- [Initial parent draft](/design/compfuzor-runtime/composition-draft0.gpt6a.md):
  explicit membership and nested operations; not a destination to confirm.
- [Confext inputs](/design/confext/build-inputs1.fx.md): concrete evidence for
  the build-only target, not proof of general isolated rendering.

## Checkpoints

### Experiment 1 — parent assessment

[Sol's report](/design/compfuzor-runtime/experiment1.sxh.md) and the scratch
`kernel/{contracts,library,runner}.ts` and `consumers/selection.ts` were read.
Reported demo/typecheck results are accepted; no duplicate verification run.

**Useful reinterpretation:** capability providers do not own every consumer's
composition. Consumers author reusable programs; CLI routes become a view rather
than the core. Reusing the status program within apply is concretely demonstrated.

**Not yet demonstrated:** broad easy contribution. `selection.ts` hard-codes
source names per contract, `Library.require()` requires exactly one matching
provider per subject, and `Program` remains a flat sequence of stage/call arrays.
Thus implementation choice (one provider) and additive contribution (many useful
pieces) are conflated. Adding a new independently useful source may require
editing consumers. Moreover source names are self-declared labels in the toy,
not authenticated trust; its acceptance mechanism is composition filtering, not
a security boundary. Do not let the next probe become primarily security plumbing.

**Next experiment:** distinguish choosing a capability implementation from
collecting independently contributed work, and make programs reusable/discoverable
contributions too. Test whether a new module can enrich an intended composition
without edits to its consumer, while that consumer can still deliberately bind
its contribution set. Require execution-result interpretation (an observation ran
successfully but its postcondition is false) to avoid a merely printable planner.
Nested composition and plan stability should be exposed by those examples rather
than solved as a speculative universal graph.

### Experiment 2 — parent assessment

Read [the report](/design/compfuzor-runtime/experiment2.sxh.md) and scratch
`kernel/{catalog,plan,run}.ts`. Accept reported demo/typecheck evidence without
rerunning. The separation between **many contributed entries** and **one chosen
implementation** is useful. Programs registered by independent modules and
composed by ID are a stronger answer to broad participation than experiment 1.
The contribution-set concept deserves keeping; the name `scope` may collide with
existing user/system scope and should not become terminology by accident.

**Important rejection:** program/query equality must not imply execution reuse.
`plan.ts`'s global `seen` plus `run.ts`'s no-op reuse nodes can suppress a second
status after intervening changes. Deduplicating overlapping collection selectors
is different from deduplicating two authored calls. Default authored calls should
be occurrences; explicitly shared invocation identity, if offered, needs separate
semantics. No inferred memoization of effectful or observational programs.

**Deeper limits:** the kernel hard-codes `ready` interpretation and script
transport, and most extensibility still means bags of executable entries.
Claims are local to one collection, not physical output identity. ID sorting
does not establish prerequisites. These are acceptable probe limitations, but
not features to bless as the backbone.

**Experiment 3:** move to contributed data with domain interpreters. Use real
scratch bytes, explicit ownership, two genuinely opposite link layouts and a
build-only confext directory from the same declarations. Ask whether this changes
the core beyond call scheduling, and where producer/consumer prerequisites live.
Keep domain result interpretation outside the generic runner where possible;
demonstrate repeated observation rather than inherited automatic program reuse.
No host publication or extension activation. The experiment must expose output
relationships, not merely register an opaque `confext.build` action.

### Experiment 3 — parent assessment

Read [the report](/design/compfuzor-runtime/experiment3.sxh.md) and scratch
`kernel/model.ts`, `programs/material.ts`, and `domain/material.ts`. Accept
reported demo/typecheck results. Real opposite links, file modes, selection,
producer prerequisites and confext-shaped output make this the strongest
material evidence yet. Descriptions and callable operations are complementary;
placement is not meaningfully recoverable from opaque handler lists alone.

**Limits that matter to backbone design:** the generic-looking kernel model
still names the material domain directly; several contributed programs are thin
forwarders to one powerful domain object. This does not yet demonstrate a common
extensibility seam for unrelated domains. `inspect()` gets expected hashes from
an in-memory WeakMap keyed by plan: a fresh invocation can no longer detect byte
drift reliably. `buildConfext()` regenerates selected material rather than proving
reuse of existing build materials. Status currently requires an exposure link,
so artifact-only material health is not independently described. These are
architectural questions, not demands to polish the throwaway implementation.

**Experiment 4:** test a single coherent library/runner across processes and
domains. A checkout-local executable exposes a scratch global entry using its
own registered installation operation, then the global entry operates on a
different not-yet-created project. Preparation is an explicit first-write
precondition (ordinary scratch directory, not pretend btrfs support). Later
processes inspect and package persisted material evidence, detect tampering, and
distinguish reuse from explicitly requested production. Verify absence/mismatch
and required-skip behavior before misleading success or unwanted writes. Do not
hard-code every scenario into the generic dispatcher; expose any remaining need
for host-driver glue honestly. Preserve manual apply and no host activation.

### Experiment 4 — parent assessment and end of sequence

Read [the final report](/design/compfuzor-runtime/experiment4.sxh.md) and scratch
`kernel/library.ts`, `checkout/cli.ts`, `domains/{material,confext,preparation}.ts`.
Accepted reported subprocess/demo/typecheck evidence. Parent found the fixed
confext release basename under custom output names; Sol corrected it within
experiment 4, checked the upstream rule, reran demo/typecheck, and committed a
report revision. No actual systemd validation/activation was performed.

The four-experiment sequence is complete. No fifth probe or implementation is
authorized by these results.

**Retain as architectural evidence:**

- Collection of many declarations differs from selecting one implementation.
- Programs as contributions are useful; an invocation context can bind chosen
  modules, domain implementations, and an explicit project target.
- Structured material descriptions enable multiple consumers without executing
  the original installer or reconstructing its intent from shell code.
- Ordinary checkout-local capabilities can expose a global entry without an
  already-installed runtime; executable location is not deployment identity.
- Realization, exposure, and artifact state require separate observations.
- Persisted realization evidence permits fresh-process inspection and packaging
  existing bytes without implicit regeneration. This does not establish that
  every legacy material must first acquire a CFR-owned receipt.
- Repeated authored calls are occurrences. Selection overlap can be deduplicated;
  program/query equality alone does not justify execution reuse.

**Reject a claim of a completed backbone:** experiment 4 is a small dependency
binding/registration mechanism and async dispatcher. Its Request envelope is
scenario-shaped; its generic type assertions do not validate contracts; its
program descriptions do not describe executable composition before execution.
The earlier plan tree, broad/narrow CLI semantics, and general execution policy
have not been combined with the final multi-domain model. Domains still embed
important dependencies and refusal behavior themselves. These probes establish
compatible ideas in parts, not a fully integrated architecture.

**Recommended reinterpretation:** CFR is a composable runtime environment for
domain modules. The registry describes available data, implementations, and
programs; a selected invocation context supplies bindings and targets; domain
modules interpret declarations; the runner interprets inspectable program
composition and execution policy. Ansible is a producer/consumer of this system,
not its sole author. CLI paths and generated bins are views of public program
structure, not the source of its meaning.

The next design should explicitly reconcile ordinary TS authoring with structured
program composition. Candidate: modules construct a small inspectable program
algebra (calls, selections, sequencing, and bounded result-dependent continuation),
while domain operations remain ordinary implementations. Do not assume this is
the selected API: compare with explicit planning methods and effect-based
interpreters, explaining where each loses truthful inspection. Dynamic continuation
may expose only a known prefix before execution; display that boundary rather
than pretending to know future work. Opaque legacy operations remain honest leaves.

**Human checkpoint:** discuss that backbone direction before implementation.
Favor a deliberate replacement of the current partial catalog/flow authority
while retaining useful CONFIG/LINKS/Zim and rendering implementations. Avoid
premature global task graphs, mandatory receipts for all legacy inputs, forced
confext dependency on a fully project-contained layout, and a new round of toy
experiments by default. The desired authoring experience still needs explicit
attention: easy independently contributed modules, discovery by scripts, tags,
narrow/broad paths, and phase/consumer relationships must not be lost in kernel
minimalism.

Completion means architectural learning, not acceptance of the prototype.
