---
type: ProblemBrief
title: Runtime composition, contribution identity, and material placement
description: Handoff brief for designing a discoverable runtime registry and compositional command language, tested against apply, confext, and project-contained layouts.
resource: /design/compfuzor-runtime/composition-problem0.gpt6a.md
tags: [runtime, composition, registry, flows, confext, filesystem]
status: draft
generated: { by: 'model:gpt-6-astra', at: '2026-09-26' }
sources:
  - id: discussion
    resource: cotail://ses_f2198adecffeZm5gWy0G9BCV3h
    title: quiet-tiger — operator direction and runtime/confext discussion
  - id: composer
    resource: /library/filter_plugins/bin_composers.py
    title: Existing action compositor
  - id: apply
    resource: /design/compfuzor-runtime/apply-flow0.glm53.md
    title: Apply composition investigation
---

# Runtime composition: problem and handoff

## Why this work exists

Compfuzor has useful contribution and script-composition machinery, and a very
new runtime that partly describes and executes its results. The operator wants
the runtime to become a registry and composition system in its own right:
pieces should contribute easily, scripts should discover who hooks into what,
and library tools and the CLI should expose a coherent hierarchy of operations.

The immediate deliverable motivating this exploration is **building systemd
confext artifacts** from generated materials, initially the systemd-iface
playbooks. Installing or activating those extensions is not in scope now.
However, a narrow packager that sidesteps the broader single-tree and runtime
questions is not the desired architectural destination.

The runtime is barely used and unvetted. Existing types, flow names, schemas,
and implementation language choices are evidence to assess, not constraints
that must survive. Significant rework is welcome when justified.

## Operator direction to preserve

- **Specificity should be navigable.** An enduring pattern is adding filename
  components to select a narrower action and removing components to run the
  broader composition. Reflect that in library tools and the runtime CLI
  (`cfr` is the proposed short name), not only generated filenames.
- **Identity should be visible.** An action should describe what it is and
  where it fits, including in its executable name/path.
- **Contributions should be easy and broad.** TypeScript modules exporting
  standard self-description, including tags, are a desired direction. Scripts
  must also be able to query the registry and participate.
- **Take a bold pass at the single-tree problem.** Describe material locations,
  exposure locations, relativity, and link direction explicitly enough for
  runtime to understand and use them. “Containered” is an unsatisfactory name
  for a capability not limited to containers. Material/exposure/placement is
  a potential framing, not a required domain model; alternative concepts are
  welcome if they make these behaviors understandable.
- **Reuse declared link information where useful.** Confext selection could
  use regexes or a full gitignore-like rule language with selection rather
  than exclusion as its purpose. `fd`/`rg` are possible exploratory tools.
- **Preserve execution controls.** Composition must not silently auto-run
  apply or defeat bypasses. Building an artifact must not imply activating it.
- **Early shared runtime is on the table.** The operator is willing to make
  runtime bootstrap an early Compfuzor obligation and assume stronger host
  prerequisites. A common installed runtime, possibly with built-in actions,
  may be preferable to redistributing a runtime into every deployment. Do not
  preserve per-deployment distribution as a requirement. Verify existing
  executable/alias arrangements rather than assuming `cf-r` or `cfr` already
  exists. Explain bootstrap ordering, version compatibility, and the behavior
  when the common runtime is missing. This also opens a credible executor for
  pre-write project preparation; it does not eliminate bootstrap dependencies.

### Hypotheses, not requirements

The operator's latest intuition is that **a phase might imply a group in that
phase**. Actions may also have multiple homes or consumers, and action-local
metadata alone might be too bottom-up: perhaps explicit bridging data should
connect an action to multiple useful compositions. An apply operation followed
by a related status operation is the motivating example. The operator explicitly
leaves open whether this multiple-home concern needs new machinery.

Do not convert these hypotheses into a fixed graph framework before testing them.

## What drives composition today

Verified by source inspection during this session; this is not an execution test.

1. Playbooks and subsystem generators accumulate `BINS` records.
2. [`bin_composers.py`](/library/filter_plugins/bin_composers.py) classifies
   leaves using explicit `action` or filename conventions. Default actions are
   `build`, `install`, and `apply`. It reads `subsystem`, `scope`, `phase`,
   `compose`, and contributor attribution.
3. [`gen_bins.tasks`](/tasks/compfuzor/gen_bins.tasks) merges generated compositor
   records back into BINS. Composition is two-level: action/scope root → subsystem
   compositor → leaves, with ungrouped leaves directly under the root. Hyphens
   are not currently an arbitrary recursive hierarchy.
4. Phases are `packages`, `identity`, `main`, `units`, `records`. Leaves sort
   stably by phase, preserving input order within each lane. A subsystem is
   placed at its earliest member's phase and executes as a group. Consequently,
   phases are **not global barriers** across nested subsystem leaves.
5. Generated records hold `run_all` lists. Assembly and deployment-time execution
   are distinct: [`bins_run.tasks`](/tasks/compfuzor/bins_run.tasks) uses fields
   including `run`, nonempty `args`, `become`, and certain inline `exec` forms.
   [`compfuzor.includes`](/tasks/compfuzor.includes) gates that whole lane with
   `BINS_RUN_BYPASS`; this does not prove later runtime calls inherit the policy.
6. [`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py) translates
   parts of this result into actions and flows. It recognizes apply actions but
   emits only build/install/status flows. Runtime is presently a consumer of a
   partial translation, not the common composition authority.

This split duplicates naming and assembly knowledge and makes a new operation
depend on coordinated updates. Existing behaviors worth preserving include
attribution, stable order, explicit opt-outs, scope, inspectability, and manual
invocation of disruptive apply operations.

## Concrete design tests

| Test | Question it forces |
|---|---|
| `apply/network` and narrower leaves | Does removing path components select a meaningful broader operation? |
| Apply then related status | Can one operation reuse another action without changing its identity or creating accidental recursion? |
| One leaf in several compositions | Is membership declared only on leaves, only on consumers, or by bridge records? |
| Mixed-phase subsystem | Is grouping atomic, are phase groups barriers, or can an execution plan split a navigational group? |
| System/user and several deployments | What is identity, what is a query qualifier, and what selects the execution target? |
| Build iface confext | Can a plan select rendered files by intended destination and produce a valid artifact without publication? |
| Project-contained layout | Can bytes move under one root while exposure relationships and artifact destinations remain understandable? |
| Btrfs project preparation | Can required preparation occur before checkout or the first write, rather than being added as a too-late build leaf? |

For confext, static-only supplies a standalone `.network` file; extra-addr
supplies a drop-in for a governing network file, with explicit discovery inputs
possible. Existing rendered bytes plus `links.json` are useful inputs, but the
link plan is not a complete package manifest: permissions and payload selection
need explicit treatment. A source-inspected no-publication route preserves link
compilation and disables BINS execution; it has not been tested as a fresh render
and is not a generic sandbox.

## Decisions still open

1. **Path meaning:** canonical action identity, composition entry point, alias,
   or some combination? How do logical paths map to existing hyphenated names
   without ambiguous parsing?
2. **Phase meaning:** label, ordered group, global barrier, or local scheduling
   slot? What happens when a grouped subsystem spans phases?
3. **Membership:** action-local metadata versus consumer selectors versus explicit
   invocation/membership records. How are exclusions and overrides explained?
4. **Reuse:** when do two selected references mean one execution versus two
   deliberate invocations with different arguments, roles, or targets?
5. **Scope and relativity:** which roots and targets are named, and when are
   locations resolved? Containment alone does not guarantee relocatability.
6. **Distribution:** statically bundled TypeScript contributions, dynamically
    imported trusted modules, generated descriptors, or a combination? How does
    early host-wide runtime installation change contribution loading, built-in
    actions, project portability, and version expectations?
7. **Policy:** automatic execution, explicit invocation, concern-specific bypass,
   and generation bypass must remain distinguishable.
8. **Selection:** namespace, precedence, negation/re-inclusion, missing matches,
   symlinks, hidden files, and directory traversal must be specified.

## Handoff assignment and evidence standard

Design a small contribution interface and a common assembly model that work
through the examples above. Compare substantially different shapes, not just
different names for the same registry. Show authored module/declaration examples,
CLI discovery and invocation, the resulting plan, and an explanation of membership
and order. Show how legacy BINS participates and what can be deleted or replaced.

### Drafting guidelines for independent proposals

These are tools for thought and comparison, not a mandatory template or a demand
to solve every question in one draft:

- Show what authors write and what users discover and invoke.
- Walk representative shared examples: narrow/broad apply, apply followed by
  related status, mixed phases, multiple consumers, and an iface confext build.
- Explain where ordering and reuse are defined, what existing machinery is
  retained or deleted, and what the design deliberately makes difficult.
- Consider early shared runtime bootstrap and built-in capabilities alongside
  contributed modules; state which host requirements the proposal assumes.
- Propose your own domain model and allocation of responsibility. A single
  registry/assembly engine, explicit membership records, universal hierarchy,
  and phase groups are all open to challenge. Seek coherent alternatives, not
  cosmetic variations of a presumed answer.

For an independent wave, do not read the linked first answer draft or other
agents' current-wave drafts before committing your own. The problem brief,
prior research, apply proposal, and existing code are shared background. Later
cross-review will deliberately bring the different answers together.

Separate verified current behavior, operator requirements, and proposed semantics.
Do not assume a runtime rewrite is necessary or that compatibility requires
preserving the current partial catalog model. Do not install confexts, reconfigure
networking, migrate project storage, or change implementation as part of this brief.

**Readiness:** enough alignment exists to draft interfaces now. More abstract
questioning is unlikely to help as much as walking concrete examples. Before
implementation, review path semantics, phase grouping, invocation multiplicity,
execution policy, and material placement with the operator.

## Cross-references

- [First answer draft](/design/compfuzor-runtime/composition-draft0.gpt6a.md) —
  one proposed answer, deliberately separate from this problem statement.
- [Apply-flow proposal](/design/compfuzor-runtime/apply-flow0.glm53.md) — concrete
  composition gap, manual apply requirement, and non-binding migration ideas.
- [Original execution model](/design/config-anneal/execution-model0.gpt6.md) —
  prior contributor/action/invocation vocabulary to reconcile rather than duplicate.
- [Runtime assessment](/design/confext/runtime0.sm.md) — current execution limits
  and separation of post-render packaging from pre-write storage preparation.
- [Confext builder inputs](/design/confext/build-inputs1.fx.md) — corrected payload,
  mapping, bypass, and upstream format evidence; use over predecessor mistakes.
- [Filesystem archaeology](/design/confext/archaeology0.fx.md) — historical context;
  read its correction notice. SteamOS bind-mount success did not solve single-tree
  portability, and confext alone does not solve it either.
