---
type: DesignProposal
title: Named operations assembled from registered contributions
description: First proposed interface separating action identity, operation membership, ordered phase groups, and material placement.
resource: /design/compfuzor-runtime/composition-draft0.gpt6a.md
tags: [runtime, composition, registry, flows, confext, filesystem]
status: draft
generated: { by: 'model:gpt-6-astra', at: '2026-09-26' }
sources:
  - id: brief
    resource: /design/compfuzor-runtime/composition-problem0.gpt6a.md
    title: Problem brief and operator direction
  - id: prior-model
    resource: /design/config-anneal/execution-model0.gpt6.md
    title: Earlier action and invocation model
---

# Named operations, registered contributions

## Position

We should make the runtime the place where contributions become an inspectable
composition, not merely a reader of compositions already hidden inside generated
shell scripts. The interface should preserve the intuitive command hierarchy:
**add path components to narrow an operation; remove them to select its broader
composition.**

My proposed answer is a registry with explicit **operation memberships** between
registered actions and named operations. Phase groups belong to the consuming
operation. This is a first draft, not an accepted schema; all TypeScript and CLI
examples below are proposed syntax, not runnable interfaces available today.

## 1. Identity and a home are related, but not identical

An **action** is a reusable executable capability. An **operation** is a named,
composable entry point. An **invocation** is a particular use of an action,
with arguments, target, placement, and policy. A **membership** places an action
invocation or another operation inside an operation.

For a simple contribution, its primary operation path and action identity can
coincide. An author should not need three declarations for the common case;
helpers can expand a short declaration into explicit registry records.

But they must be distinguishable when reuse matters:

```text
status/network/address        canonical reusable action / primary entry point
apply/network → verify-address   another membership invoking that action
```

The second home does not rename the action to `apply/network/status`. This
avoids forcing execution sequence and reusable identity into the same tree.

Names are segment arrays internally, not reparsed hyphenated strings. A legacy
name such as `apply-networkd.sh` retains an explicit mapping. We should not
guess whether each hyphen in a subsystem name introduces a new hierarchy level.
Generated wrappers may preserve existing filenames or use nested paths; the
mapping must be inspectable and collisions rejected.

## 2. A contribution module exports declarations

Modules export data and handler references rather than mutating a global registry
at import time. Registration validates and collects; it does not run actions.
Executable modules remain trusted code: importing arbitrary TypeScript is not
safe merely because the exported description is declarative.

An intentionally explicit sketch, before authoring conveniences:

```ts
export default defineContribution({
  id: "systemd.network",
  tags: ["systemd", "network"],
  actions: [
    {
      id: "apply/network/reconfigure",
      handler: { kind: "exec", path: "bin/apply-networkd.sh" },
      tags: ["network", "disruptive"],
    },
    {
      id: "status/network/address",
      handler: { kind: "module", run: inspectAddress },
      tags: ["network", "inspection"],
    },
  ],
  memberships: [
    {
      id: "network.apply.reconfigure",
      operation: "apply/network",
      action: "apply/network/reconfigure",
      phase: "change",
    },
    {
      id: "network.apply.verify-address",
      operation: "apply/network",
      action: "status/network/address",
      phase: "verify",
    },
  ],
});
```

Action identity is qualified by contribution source/deployment in the registry;
the execution context must select which deployment is intended. Example strings
are local names, not a claim of global uniqueness across every installed project.

Legacy BINS, external script descriptors, and TypeScript modules should produce
the same normalized records. Bundle-time discovery and dynamically loaded modules
are separate delivery adapters. Preserve self-contained runtime distribution
while investigating whether optional external modules are worth supporting.

## 3. Membership is the bridge, not a mandatory burden on every action

The registry collects actions and memberships independently. A consumer may
therefore contribute an operation using actions supplied elsewhere, without
editing their original modules. Action-local shorthand can contribute ordinary
memberships; it is convenience syntax, not a separate composition engine.

Selectors over names, tags, and contributors can generate memberships. Assembly
must record the matching rule and resolve it into a fixed plan before execution.
Late contributions do not silently enter an already-running operation.

Do not automatically add status after every apply. The consumer declares the
relationship and chooses which status is relevant. A check used to guard an
apply is not automatically the same check that verifies its result. A status
action also needs declared result semantics if failure should fail the apply.

Membership identity distinguishes intentional repetitions. Selecting the same
membership through overlapping rules should not duplicate it; two differently
named memberships invoking the same action remain two invocations. Explain that
distinction in the plan. Reject cycles and conflicting duplicate declarations.

## 4. Phases are ordered groups, local to an operation

The operator's phase/group intuition is worth adopting experimentally:

```text
apply/network
  prepare
    inspect governing configuration
  change
    publish selected configuration
    reload / reconfigure
  verify
    inspect address and route
```

Here a phase is a real group in the execution plan, with ordering between groups.
It is not automatically a permanent component of action identity or CLI path.
One action can occupy different phase groups in different operations.

The unresolved hard case is cross-subsystem ordering. This draft chooses:

- Phase ordering is **local**, not a magical global barrier.
- A referenced child operation keeps its internal composition together.
- A parent needing “all changes, then all verification” must select the relevant
  memberships into its own change/verify groups rather than invoke whole child
  operations serially.
- That selection must be explicit and explained; the planner does not silently
  split a child operation to satisfy an inferred ordering preference.

This preserves meaningful grouped operations while permitting broader phase
composition. It is also a complexity risk: test whether authors actually need
both forms before adding elaborate projection syntax. Start sequential; do not
equate a phase group with permission to run its members concurrently.

## 5. CLI navigation and library tools expose the same plan

Proposed examples:

```sh
cfr list apply/network
cfr explain apply/network
cfr plan apply/network --scope system
cfr run apply/network
cfr run apply/network/reconfigure
cfr query actions --tag network --json
cfr query memberships --action status/network/address --json
```

`run apply` selects the broader declared composition. A prefix query may discover
descendants, but execution requires an assembled operation: lexical proximity
alone must not turn every registered command into executable membership.
Conventions can synthesize parent operations so authors rarely need boilerplate;
the registry should show that these memberships were convention-generated.

The library counterpart should be small: load/register contributions, query,
assemble, and execute or emit. An assembled plan records provenance, resolved
targets, membership, ordering, policy decisions, and handler references. Shell
wrapper generation should consume that plan instead of rerunning a parallel
composition algorithm. Not every native handler can become standalone shell;
wrappers may invoke runtime for those entries, and that dependency must be explicit.

## 6. Material placement is a related domain, not a disguised command tree

A material needs stable identity, a location containing its bytes, and intended
consumer locations. Named roots describe relativity, such as `project`,
`system-config`, and `artifact`. Layout resolution produces placement relations:

```text
system-oriented:   system location holds bytes; project exposes a reference
project-contained: project holds bytes; system exposes a reference
confext output:    artifact receives bytes at its own etc/... destination
```

Changing layout is not merely swapping two strings on an existing symlink.
An already populated deployment needs an explicit migration operation; the
initial layout declaration must not move or delete existing state implicitly.
Copy, symlink, and artifact projection have different semantics and constraints.

For confext, select by **intended destination namespace**, using ordered
gitignore-like include/exclude rules over declared materials. Start empty;
positive rules select, `!` rules deselect, later matches win. Evaluate an
enumerated material set so directory pruning does not obstruct re-inclusion.
Regex can be another explicit matcher. This borrows familiar syntax without
claiming full Git ignore semantics.

The builder consumes selected resolved materials, permissions, and extension
metadata, and emits a directory or chosen image form. It must not invoke the
host install/apply flow to obtain them. Use `links.json` as an input adapter for
the pilot, not as proof every link is packageable. Reject escaping paths,
conflicting destinations, and unresolved output-mode decisions. Validate symlink
handling explicitly; do not silently dereference arbitrary host content.

The registry can discover material contributors and expose their provenance,
while a packaging module owns projection and format-specific validation. Sharing
discovery does not require a universal type that treats files as executable actions.

## 7. Policy and lifecycle are first-class constraints

Preserve distinctions among generation bypass, automatic-run bypass, explicit
invocation, and concern-specific execution restrictions. The compatibility
adapter must document what `BINS_RUN_BYPASS` means; do not silently reinterpret
it as either a permanent execution ban or permission for later runtime calls.

Manual apply remains manual. A composed post-apply status runs only when the
apply operation itself is explicitly invoked. A skipped prerequisite must not
leave a dependent action running as though it succeeded; plans need an explicit
skip/failure policy rather than treating every bypass as ordinary success.

Btrfs preparation exposes a lifecycle limit: a runtime installed into a project
cannot prepare that project's subvolume before its own installation. A controller
or already-available runtime must invoke pre-write preparation. A contribution
registry can describe that requirement, but cannot erase the bootstrap dependency.
Snapshots are separate later operations, not synonyms for initial preparation.

## 8. How to test and revise this answer

Before implementation, walk these examples with authored declarations and exact
plans: one apply leaf; two subsystem groups spanning phases; shared status used
by both status and apply; a duplicate selector match versus intentional repeated
invocation; the same action across two deployments; contained versus system layout;
and an iface confext built without host publication.

The first implementation experiment should prove common assembly and explanation
over legacy BINS plus one native module, without activating networking. Then use
that model for confext material selection and output. Compare generated wrapper
and runtime execution order, bypass decisions, attribution, and failure behavior.
Do not preserve today's schema merely to avoid a version change.

The strongest reason to reject this draft would be if explicit memberships and
local phase groups make ordinary contributions harder than current BINS. The
strongest reason to keep them is that they give reuse and consumer-owned composition
a precise home without destroying readable primary command paths.

## Cross-references

- [Problem brief](/design/compfuzor-runtime/composition-problem0.gpt6a.md) — operator
  requirements, current implementation background, open decisions, and handoff scope.
- [Apply-flow proposal](/design/compfuzor-runtime/apply-flow0.glm53.md) — concrete
  consumer of shared assembly and the manual-invocation requirement.
- [Original execution model](/design/config-anneal/execution-model0.gpt6.md) —
  existing action/invocation vocabulary; reconcile membership with its model
  before introducing redundant public concepts.
- [Confext input research](/design/confext/build-inputs1.fx.md) — evidence for
  rendered-material and link-plan reuse, plus remaining permission differences.
- [Runtime assessment](/design/confext/runtime0.sm.md) — limits on current
  catalog authority, side-effect containment, and pre-write lifecycle support.
