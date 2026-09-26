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

Pending: experiment 1. Assessments will be recorded as experiments complete;
completion means architectural learning, not acceptance of the prototype.
