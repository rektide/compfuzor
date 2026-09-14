---
type: ArchitectureCheckpoint
title: Contributed flows and execution policy
description: Annealed model for attributed contributors, plural composition, lexically ordered flows, and cross-plane suppression in compfuzor-runtime.
resource: /design/config-anneal/execution-model0.gpt6.md
tags: [compfuzor, runtime, contributors, composition, flows, attribution, bypass, ansible]
status: draft
generated: { by: model:gpt6, at: 2026-09-14 }
verified: { by: unverified }
stale_after: 2026-10-14
sources:
  - id: ordinary-use-cases
    resource: /design/config-anneal/use-cases1.glm53.md
    title: Ordinary install and link use cases
  - id: exceptional-use-cases
    resource: /design/config-anneal/use-cases0.glm53.md
    title: Runtime and domain use cases
  - id: tactical-assessment
    resource: /design/config-anneal/simplification-assessment0.gpt6.md
    title: Configuration simplification tactical assessment
  - id: subsystem-architecture
    resource: /doc/subsys.md
    title: Existing subsystem contribution architecture
---

# Contributed flows and execution policy

## Status and intent

This checkpoint records the architecture annealed through discussion after the
CONFIG, LINKS, Zim, and config-remote runtimes were packaged as one
`compfuzor-runtime.mjs`. It is not an Effect migration plan and does not
authorize a new flow runner yet. The next implementation is observational: add
attribution and compile a read-only catalog of what Ansible already knows.

The central change in perspective is:

> Contributors inject attributed data and structured invocations into a small
> set of flows. They do not generate another wrapper or compositor by default.

Generic CONFIG contexts survive and advance. Systemd and Zim remain first-class
built-in domains. Shared effects do not erase domain ownership or sequencing.

## Why the current shape needs annealing

A BINS record currently combines too many responsibilities:

1. executable materialization;
2. command definition;
3. aggregate-flow participation;
4. scope and subsystem grouping;
5. ordering phase;
6. bypass policy;
7. shell helper selection; and
8. render-time automatic execution.

`bin_composers.py` infers `build`, `install`, or `apply` from filenames or one
explicit field, groups records by scope and subsystem, orders them through
lanes, and emits shell wrappers. The ordinary-use survey found that `build` and
`install` dominate while `apply` has only two authored leaves, and that
`install` currently means acquisition, compilation, publication, registration,
activation, adoption, or aggregation depending on the caller.

The desired model separates command availability from flow participation and
separates both from primitive effects.

## Vocabulary

| Term | Meaning |
|---|---|
| **Contributor** | One attributed participant that provides domain data, actions, observations, or flow composition. Usually projected from an existing Ansible subsystem or the invoking playbook. |
| **Descriptor** | Runtime-readable metadata describing a contributor or action. |
| **Resource** | Versioned domain data consumed by an action, normally referenced through an existing domain spec rather than embedded in a universal index. |
| **Action** | A stable callable interface owned by a contributor, such as `links.apply` or `zim.install`. |
| **Invocation** | One action plus fixed arguments, resource bindings, scope, and outcome protocol. |
| **Flow** | An ordered operator-level aggregate. The initial flows are `build`, `install`, and `status`. |
| **Composition** | A contributor's declaration that a record participates in one or more flows. |
| **Phase** | A semantic range within one flow's `01–99` lexical order. |
| **Operation** | Domain behavior behind an action. |
| **Effect** | One bounded mutation or observation used by an operation. |
| **Provider** | An adapter implementing an effect seam, such as the external `block-in-file` executable. |
| **Representation** | One accepted physical form of the same relationship, such as whole-entry copy or link. |
| **Observation** | A typed account of actual state relative to declared state. |
| **Execution policy** | Explicit omit/skip control addressed by execution plane and target, compiled from ergonomic bypass inputs. |

Use **flow**, not workflow, for Compfuzor's build/install/status aggregates.
“Workflow” remains available for Effect's durable workflow facility, which is
not presently justified for local convergent installation.

## Architectural shape

```text
Ansible playbook
    |
    v
attributed SUBSYSTEM envelopes and direct playbook contributions
    |
    +---- domain specs: config.spec.json, links.json, zim.spec.json, ...
    |
    +---- normalized composition declarations
                    |
                    v
          contract-specific composition adapters
                    |
                    v
          one structured invocation per indexed file
                    |
                    v
       compiled/NN-FLOW-SLUG.json + site overrides
                    |
                    v
          read-only runtime catalog (first)
                    |
                    v
          flow execution (deliberately later)
```

The runtime catalog is a routing and explanation structure, not a universal
domain plan. It references separately versioned domain resources.

## Contributors and attribution

### Reuse the existing subsystem model

`SUBSYSTEM.<id>` already carries control state, `spec`, and `contrib`. A runtime
contributor should be a safe projection of that envelope, not a parallel
authored ontology.

Add attribution that distinguishes:

| Relationship | Example | Meaning |
|---|---|---|
| `requested_by` | `playbook:jujutsu-main` | The deployment/playbook that activated the behavior. |
| `contributed_by` | `subsystem:rust` | The subsystem that produced the record. |
| `synthesized_by` | `gen_rust`, `compile.synthesis` | The stage that derived or merged the final artifact. |

Example envelope:

```yaml
SUBSYSTEM:
  rust:
    attribution:
      requested_by:
        id: playbook:jujutsu-main
        playbook: jujutsu.src.pb
        deployment: jujutsu-main
      contributed_by:
        id: subsystem:rust
        domain: rust
      synthesized_by:
        stage: compile.synthesis
        generator: gen_rust
    requested: true
    active: true
    spec: {}
    contrib: {}
```

### Reference attribution from artifacts

Synthesized artifacts carry stable contributor IDs; full attribution lives once
in contributor envelopes:

```yaml
name: install-rust.sh
contributors:
  - playbook:jujutsu-main
  - subsystem:rust
```

This generalizes the existing BINS-only `origin_subsystems` mechanism. Scalar
artifact families such as `PKGS` may use a catalog-side reverse index rather
than replacing every scalar with an envelope.

### Safe direct projection

“Direct dump” means preserving existing shapes where safe, not serializing all
Ansible variables. The catalog projection must omit secrets and controller-only
objects:

| Existing family | Safe catalog projection |
|---|---|
| `BINS` | Name, action, scope, phase, run/compose state, command path, contributor IDs; omit generated shell bodies. |
| `ETC_FILES` | Identity/path/mode/source kind; omit secret inline content. |
| `LINKS` | Existing record shape plus contributor IDs. |
| `PKGS` | Package declarations and reverse contributor index. |
| `STATUSES` | Reporter name, fixed arguments, protocol, contributors. |
| `TOOL_VERSIONS` | Existing tool/version declarations. |
| `ENV` | Keys and provenance only; values remain in protected env resources. |
| Domain `spec` | Contract identifier, version, and resource path. |

Unattributed legacy records remain visible and are labeled honestly rather than
assigned guessed provenance.

## General plural composition

### Accepted locations and normalization

Any contributed record may carry `composition`: a resource record, subsystem
or spec envelope, command record, or status provider. A mapping is shorthand
for one item; a list declares several. Existing
`normalize(to='list')` supplies the authoring normalization.

```yaml
composition:
  flow: install
  phase: publish
```

```yaml
composition:
  - flow: install
    phase: publish
  - flow: status
    phase: inspect
```

### Authoring fields

| Field | Meaning |
|---|---|
| `flow` | Required flow name. Initially `build`, `install`, or `status`. |
| `phase` | Semantic placement resolved through that flow's phase chart. |
| `index` | Optional precise `01–99` placement. If combined with phase, it must fall within the phase range. |
| `scope` | Optional one-or-many scope selection. |
| `action` | Optional; the owning contract supplies its normal flow-specific action. |
| fixed input | Optional arguments or typed resource/context bindings understood by the action contract. |

The compiled invocation is explicit even when authoring uses defaults.

### Defaults

The accepted rule is:

```text
composition omitted       -> owning contract's documented conservative default
composition: false        -> direct-only; joins no aggregate flow
composition mapping/list  -> authored declarations replace the contract default
```

Defaults reduce repetitive authoring but never remain implicit in compiled
output. Catalog provenance distinguishes `contract-default`, `authored`, and
`authored-false` composition.

Specialized generators may synthesize explicit composition. For example, a
high-level global-bin declaration may generate a LINKS record with explicit
install/publish and status composition.

### Contract-specific lifting

Common machinery normalizes and validates composition, resolves phase/index,
attaches attribution, and writes indexed invocation files. The owning contract
decides the default action, resource binding, and batching:

```text
LINKS adapter
  many compatible records -> one links.apply invocation with resource IDs

systemd adapter
  many units -> one systemd.install invocation per manager/scope

Zim adapter
  one host spec -> zim.install and zim.status invocations

legacy BINS adapter
  one executable record -> one external-command invocation
```

Generic batching is rejected because only a domain contract knows whether
several records can share one action call.

## Flows and lexical order

### Initial flow vocabulary

The initial operator aggregates are:

- `build`
- `install`
- `status`

`apply`, `assemble`, `publish`, `activate`, `import`, and `remove` remain
qualified domain actions. Existing global `apply.sh` behavior is compatibility
surface pending inspection of its two current users.

### Workflow-specific phase charts

Phases are defined per flow and map onto visible `01–99` ranges. The exact
ranges below are an initial chart to verify against generated catalogs.

#### Build

| Range | Phase |
|---:|---|
| `01–19` | prerequisites |
| `20–39` | prepare |
| `40–69` | compile |
| `70–89` | package |
| `90–99` | finalize |

#### Install

| Range | Phase |
|---:|---|
| `01–19` | prerequisites |
| `20–29` | identity |
| `30–49` | materialize |
| `50–69` | publish |
| `70–89` | activate |
| `90–99` | record |

Status initially preserves stable contribution order and lets the aggregate
runner summarize observations. It does not need artificial domain phases.

### One invocation per file

Compiled filenames use:

```text
NN-FLOW-SLUG.json
```

Examples:

```text
10-build-rust-prerequisites.json
50-build-rust.json
55-install-links-apply.json
75-install-systemd.json
80-install-zim.json
95-install-links-records.json
```

Each file represents exactly one structured invocation. Domain actions may
process many bound resource records internally. Declaration order breaks ties
within an index; complete lexical filename order is observable.

### Compiled and site layers

```text
etc/compfuzor-runtime/workflows/
  compiled/
    55-install-links-apply.json
    75-install-systemd.json
  site/
    65-install-systemd.json -> ../compiled/75-install-systemd.json
```

The compiled layer is authoritative generated state. The site layer may:

1. change placement by presenting the same stable contribution ID under a new
   lexical filename; or
2. tombstone that ID with existing `state: absent` vocabulary.

Site placement cannot silently alter action, fixed arguments, scope, resource
bindings, or outcome protocol under the same ID. Changed behavior requires a
new attributed site contribution and, if necessary, a tombstone for the
compiled one. Catalog output shows selected and shadowed paths.

## LINKS as the first ordinary data tracer

Global binary publication should use LINKS rather than a new publication
domain when the desired state is a durable whole-entry copy/link relationship.
Rust, Go, CMake, Bazel, and similar contributors inject attributed LINKS
records; the LINKS composition adapter batches compatible records into one
install/publish invocation and one status action.

Package-manager registration such as `pnpm link -g` is not a filesystem LINKS
record and remains a Node/npm domain action.

CONFIG consumer delivery may share copy/link effects without becoming durable
LINKS ownership. Systemd unit records remain LINKS-owned but may set
`composition: false` because `systemd.install` publishes selected units before
reload/enable/start. These distinctions preserve the existing ownership model.

## First-class domains and shared effects

“Generic” has two useful meanings:

1. domain-free kernel/effects: selection, process execution, file inspection,
   copy/link, managed-block mutation, and outcome folding;
2. first-class built-in domains: CONFIG, LINKS, systemd, Zim, and likely
   package/tool publication concerns.

Systemd and Zim deserve built-in actions without exposing their internal steps
to global composition:

```text
systemd.install
  publish selected units -> daemon-reload -> enable/start

zim.install
  CONFIG install -> loader blocks -> cache builds -> registry
```

The global install flow sees one invocation from each domain. Domain operations
use shared effects internally and retain sequencing authority.

Managed-block mutation is a shared sub-file effect, not a third whole-entry
representation beside copy/link. Its provider interface needs resolution,
capability probing, projection shared by apply/status, anchoring, seeding,
deliberate absence, named ownership, and refusal behavior. The external
`block-in-file` executable remains the initial provider.

## Execution policy: replacing cross-cutting bypass inference

### Three execution planes

| Plane | Meaning | Existing examples |
|---|---|---|
| `compile` | Controller decides which contributor state, specs, artifacts, and actions exist. | `ZIM_BYPASS`, `CONFIG_CONTEXTS_BYPASS` |
| `ansible-apply` | Compiled intent exists, but target effects are skipped during this playbook invocation. | `PKGS_BYPASS`, `BINS_BYPASS`, `BINS_RUN_BYPASS`, `SYSTEMD_THUNK_BYPASS` |
| `host-runtime` | Deployed actions exist, but a later local invocation is suppressed. | `COMPFUZOR_ZIM_BYPASS`, `COMPFUZOR_CONFIG_BYPASS`, nested systemd controls |

Catalog-first work records current render-time execution but does not yet decide
whether Ansible and host runtime should invoke one shared action. Trigger
unification is deferred until real catalogs can be inspected.

### Policy dimensions

Ergonomic variables and flags compile into explicit policy with:

| Dimension | Values |
|---|---|
| plane | compile, ansible-apply, host-runtime |
| target | contributor, flow, invocation/contribution, action, effect, resource |
| disposition | omit, skip |
| source | declaration, extra-var, environment, CLI, site |
| reason | human-readable explanation |

Targets form useful levels of “do not do that” without pretending they are one
boolean:

```text
plane -> contributor -> flow -> action -> flow contribution -> effect/resource
```

The evaluator matches target identity rather than deriving policy from an
executable filename.

### Accepted precedence

Suppression is initially deny-only and monotonic: any applicable omit/skip wins.
Narrower policy cannot silently re-enable a broader suppression. This maps to
today's OR-composed bypass behavior and keeps emergency controls trustworthy.

An explicit override, if ever required, must be an audited named mechanism; it
is not implicit in direct invocation.

### Direct actions and flow contributions

A direct action ignores policy addressed only to a flow or one flow
contribution. It still respects policy addressed to its action, contributor,
plane, nested effects, or resources.

This captures the current useful CONFIG intent:

```text
ordinary config.install flow contribution skipped
direct CONFIG diagnostics and repair actions remain available
```

Direct invocation is not general force mode.

### Typed outcomes

Flow execution will eventually require typed outcomes:

- `Completed`
- `Skipped`, with matched policy and reason
- `Attention`, for drift or other non-fatal observation
- `Failed`, with typed error

Legacy executable adapters may map documented exit protocols into these
outcomes. Internal leaves that callers require to produce an artifact must not
be bypassed by returning an untyped success. Domain operations own the meaning
of intentionally skipped nested effects.

Mutation suppression does not automatically suppress observation. Status
remains independently selectable and should explain the resulting actual state.

## Discovery and catalog

### Authority

The accepted discovery model is:

```text
compiled index and workflow files
  + explicit site/data drop-ins
  + later, explicit external action adapters
  -> validated deterministic catalog
```

Do not scan or execute arbitrary files under `bin/`. Built-in action handlers
live in the omnibus runtime. JSON drop-ins are data-only initially. External
executables are referenced explicitly and declare an outcome protocol.

### Inventory is not health

Catalog operations explain what is present:

```text
catalog contributors
catalog actions
catalog flows
catalog flow install --scope user
```

Status actions observe declared state. Catalog output may show which resources
have observation support, but inventory does not execute reporters.

Useful explanations include:

- why an invocation exists;
- which contributor and records produced it;
- whether composition came from a contract default or authored declaration;
- effective lexical and semantic placement;
- compiled versus site source and shadowing;
- applicable execution policy by plane;
- legacy/unattributed confidence markers.

## Language and extension posture

TypeScript with Effect is the intended maintained implementation direction.
zx is the preferred low-friction external executable adapter but is not a hard
runtime requirement. Plain Node, shell, Python, and future Rust executables must
remain possible.

A future language-neutral convention may let any executable expose a reserved
interface such as:

```text
<executable> compfuzor describe --json
<executable> compfuzor invoke <action> ...
```

The Rust path should be ticketed after the TS action, descriptor, and outcome
interfaces settle. Rust should orchestrate executables through this convention,
not require in-process plugins. The read-only catalog does not need to finalize
that protocol.

## Annealing and implementation matrix

| Work | Model value | Risk | Status/order |
|---|---:|---:|---|
| One omnibus Vite+ runtime | medium | medium | Implemented; packaging foundation only. |
| Contributor attribution in Ansible | high | medium | Next prerequisite; valuable independent of runtime language. |
| Read-only contributor/action/flow catalog | high | medium | First runtime slice; executes nothing. |
| Direct final CONFIG compilation | very high | high | Important deletion; perform with snapshots after catalog exposes current output. |
| Native composition for global-bin LINKS | high | medium | First ordinary data tracer. |
| Native CONFIG context adoption in `mcp-cli.src.pb` | high | medium | Second real context adopter. |
| Native composition for systemd and Zim | high | high | Invocation tracer after catalog/attribution settle. |
| Managed-block provider and Atuin/Mise pilots | high | medium-high | Shared-effect tracer; precedes Zim envsubst deletion. |
| New flow execution authority | very high | high | Only after native coverage and shell-order comparison. |
| Effect retyping and CLI adoption | potentially high | high | Map settled seams; do not use Effect to choose them. |
| zx no-build contributor mode | medium-high | medium | Adapter over the same descriptors/actions, never second semantics. |
| Spec consolidation | low now | very high | Deferred; domain specs express different ownership. |
| Rust orchestrator | unknown/later | very high | Future interoperability ticket, not current implementation. |

## First implementation checkpoint

The first slice is deliberately observational:

1. determine a reliable playbook/deployment identity from Ansible and add
   playbook/contributor/stage attribution to subsystem envelopes;
2. preserve contributor IDs in BINS and status synthesis, then add safe
   projections for further artifact families incrementally;
3. define flow phase charts and normalize contract defaults plus authored
   composition into explicit compiled declarations;
4. emit one invocation per `NN-FLOW-SLUG.json` under the compiled layer;
5. add read-only contributor, action, and flow catalog commands;
6. translate current BINS/STATUSES into clearly labeled legacy observations for
   order comparison, without moving execution authority yet;
7. compare catalog output with generated `build.sh`, `install.sh`, and
   `status.sh` on representative ordinary and exceptional playbooks.

No Effect service extraction, flow execution, render-trigger unification, or
live deployment belongs in this checkpoint.

## Open questions

1. Verify the best Ansible source for the invoked playbook filename; do not rely
   on `/proc/self/cmdline` if a trustworthy magic variable is available.
2. Finalize the exact `01–99` phase ranges after cataloguing representative
   deployments.
3. Decide how much legacy BINS/STATUSES inference appears in catalog comparison
   and ensure inferred entries never silently become permanent native truth.
4. Define the smallest safe redaction policy for ETC and ENV contribution
   projection.
5. Determine whether status flow composition is explicit per contributor or
   synthesized once from every domain with observable resources.
6. Decide when site drop-ins may supply executable code rather than data-only
   descriptors.
7. Define concurrency/locking before flow execution can mutate a deployment.
8. Decide whether a staged transaction remains the CONFIG shell leaf or becomes
   a shared TypeScript effect only after a second real transactional consumer.

## Cross-references

- [`use-cases1.glm53.md`](/design/config-anneal/use-cases1.glm53.md) establishes
  the ordinary majority, global-bin tracer, render/apply split, and lack of
  observation coverage.
- [`use-cases0.glm53.md`](/design/config-anneal/use-cases0.glm53.md) establishes
  the Zim, Mise, systemd, managed-block, and durable LINKS constraints.
- [`simplification-assessment0.gpt6.md`](/design/config-anneal/simplification-assessment0.gpt6.md)
  distinguishes genuine model deletions from packaging and usability work.
- [`effect-design0.glm53.md`](/design/config-anneal/effect-design0.glm53.md) is a
  downstream baseline for mapping settled seams into Effect; this checkpoint
  deliberately precedes that migration.
- [`doc/subsys.md`](/doc/subsys.md) documents the existing `SUBSYSTEM`,
  `contrib`, BINS provenance, and compositor behavior this model evolves.
- [`doc/arch.md`](/doc/arch.md) defines the current
  `raw -> probe? -> norm -> spec -> contrib? -> apply` subsystem lifecycle and
  shared-synthesis rules.
- [`doc/bins.md`](/doc/bins.md) documents the wrapper/compositor hierarchy that
  becomes compatibility input to the catalog.
- [`doc/config/consumer-toolkit.md`](/doc/config/consumer-toolkit.md) remains the
  behavioral contract for generic CONFIG contexts during annealing.
