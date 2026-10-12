---
type: ImplementationProposal
title: Make CONFIG instantiable, then join producer material through fuzings
description: A bounded implementation route using independent CONFIG specs, shared workers, native copy/link delivery, and normal ZIM operations.
resource: /design/fuzings/implementation0.gpt6a.md
status: draft
generated: {by: 'model:openai/gpt-6-astra', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed3f4aaaaffePYlWeomteOWlbg
    title: brave-meadow — multiple complete CONFIGs, implementation sizing, and isolated shared-runner proof
  - resource: /design/fuzings/contract1.gpt6a.md
    title: Current draft contract and human correction to preserve normal ZIM configuration
  - resource: /library/filter_plugins/config_compile.py
    title: Existing recipe compiler, fixed leaf paths, and singleton publication
  - resource: /files/config/assembly.ts
    title: Explicit spec/context/runner binding already available at runtime
  - resource: /files/config-remote/runtime.ts
    title: Default-spec coupling in remote input mutation and rebuild
  - resource: /doc/config/simplification.md
    title: Preserve shared engines and fixed command vocabulary without compiler rewriting layers
  - resource: /.design/config-mcp/draft1.gpt56t.md
    title: Earlier repeatable-generation proposal and two-instance isolation test
  - resource: /.design/config-mcp/draft2.gpt56t.md
    title: Earlier multi-instance and artifact-dependency proposals, not current implemented behavior
---

# Sizing and starting point

**A meaningful but bounded CONFIG packaging/binding refactor, followed by native
contribution delivery.** The core assembler does not need replacing to support
multiple complete CONFIG definitions. Normal ZIM config keeps its channel recipes,
loaders, caches, and installation operation. The
[contract](contract1.gpt6a.md#intended-instance-boundary) explains that boundary.

The full result also needs ENV normalization/serialization and shell activation.
Those are separate behavior changes; success at multi-CONFIG packaging does not
prove them. The initial implementation should make independently useful progress
without introducing a workflow engine or requiring a new candidate dependency DAG.

## What was actually exercised

On 2026-10-12 this session ran a temporary fixture under `/tmp/opencode` using the
repository's real `files/config-run.sh` and `files/config-processor.sh`:

- One shared deployment `DIR`, two separately selected `CONFIG_SPEC` files.
- Both specs used the recipe name `main`, with distinct inputs and outputs.
- Both used the same explicit `leaf` executable invoking the existing concat
  processor. No per-instance processor implementation was introduced.
- One input was a producer symlink, the other a copied producer file.
- Each spec carried a validator rejecting a `BROKEN` marker.

Both assembled independently. Updating producer bytes changed the linked result
on reassembly, but not the copied result until its input copy was refreshed. A
failed validation preserved both prior outputs, and the other CONFIG still passed
`--check`. The temporary fixture was removed after execution.

This proves the worker-level property. Specs and input representations were made
by the fixture, so it **does not prove** multi-instance Ansible generation, native
delivery API orchestration, ZIM activation, or fuzing enrollment. The first durable
integration test must extend the proof through generation and public operations.

## First landing: complete CONFIG definitions share one runtime

### Bind a complete configuration

Introduce an explicit per-CONFIG binding covering:

- its spec location;
- its material/input/output roots;
- generated/custom leaf locations;
- its contexts and default context;
- its ordinary installation owner;
- its identity in generated operations, status, and catalog inspection.

Recipe and input names remain local to that CONFIG. Two definitions can both
contain `main`, `zimrc`, or `fragments`. Actual output-path conflicts still need
rejection when assembling a deployment containing both definitions.

The authored collection syntax should be decided with the initial compiler change.
A named map of complete definitions is straightforward; a `CONFIG_ROOTS`-style
list of scoped declarations would fit the existing SYSTEMD_ROOTS convention.
Either way, call the existing recipe/context normalization for each definition.
Do not flatten their recipe maps into one CONFIG or mutate global facts between
calls and hope delayed templates retain the right values.

### Separate definition compilation from runtime packaging

Relevant changes:

| Area | Intended change |
|---|---|
| `config_compile.py` | Parameterize output/leaf bindings; compile each normal recipe set independently. Built-in recipes may point directly to shared processor leaves. Custom leaves get definition-scoped paths. |
| `config_context_compile.py` | Retain context semantics and install ownership per spec; emit the shared fixed action/runtime surface once. |
| `sub_config.tasks`, `gen_config.tasks` | Compile/publish a collection of independently bound definitions and combine their generated artifacts without overwriting one SUBSYSTEM.config slot. |
| `config/cli.ts`, `config/runtime.ts` | Carry the selected binding through all operations; existing `--spec`/`--runner` support is the starting point. |
| `config/assembly.ts`, worker invocation | Keep the deployment execution root explicit and distinct from spec/material location. Avoid inferring a new DIR just because an instance-scoped executable is nested more deeply. |
| `runtime_catalog.py` and action bindings | Advertise and bind each CONFIG's exact spec rather than always `etc/config.spec.json`; retain existing action composition. |

Reasonable packaging options are `etc/config/<id>/spec.json` with shared workers,
or domain-owned locations such as `etc/zim/config.spec.json`. Prefer the grouped
CONFIG location for the initial generator because repeated instances fit it
directly; native material can keep its established domain paths. Choosing a spec
location does not force moving ZIM's native inputs and outputs.

One runtime and fixed action vocabulary serve these specs. Use existing explicit
spec selection in the first proof; a short logical CONFIG selector can be added
once its binding is clear. Generated operation bindings can capture spec and
context directly. Avoid multiplying implementation wrappers per recipe/context.

Existing top-level CONFIGS can normalize as one default definition. That is a
small adaptation for actual current callers, not a second implementation. Existing
public default commands must select that definition unambiguously.

### Close the less-visible singleton paths

Merely writing several spec files is not enough:

- `config-remote/runtime.ts` both loads the fixed default spec and rebuilds via
  the default CONFIG command. Pass its selected spec/runner through mutation and
  rebuild, including failure recovery.
- Generated build-time canonical assembly currently emits one `run: true` worker.
  Generate bound invocations for each intended definition, rather than executing
  the shared worker once with whichever environment happens to win.
- Ordinary install and status must cover each selected CONFIG exactly once.
  `CONFIG_INSTALL_OWNER` can remain a normal per-definition setting; ZIM taking
  ownership of its own CONFIG must not disable another definition's installer.
- Inspect processor helpers, custom processor cwd/env, and action transport for
  default-spec or DIR fallback. A selected spec is not permission for producer
  environment material to rebind the executing deployment.

### Acceptance for the first landing

Generate two complete configurations into one fixture deployment. Give them the
same recipe name, input name, and context name, but different source/output roots.
Exercise public assemble/check/status and input copy/link operations independently.
Then mutate one remote input and verify its automatic rebuild selects the same
spec. Failed assembly must leave the other CONFIG's output and input state alone.
Generation repeated in reversed definition order must not change the bindings.

This is the decisive test: **two ordinary CONFIGs work without knowing about each
other**. The existing single-definition tests remain the regression baseline.

## Second landing: normal ZIM beside another CONFIG

ZIM already accepts `--config-spec` and `--config-runner` in its CLI, and its
activation binder accepts a CONFIG spec argument. Use those existing seams.
Bind generated install/import/status operations to the intended CONFIG. Keep its
local `zimrc` and `zimenv` names, normal context resolution, and complete-install
semantics. Parameterize ZIM's own spec/entrypoint binding if several ZIM instances
are requested; do not change what a ZIM installation does.

Prove a ZIM CONFIG and an ordinary JSON CONFIG coexist, each installable, with
ZIM still producing its normal channels/loaders/caches. This catches global
ownership and default-spec leakage before the fuzing resolver is involved.

## Third landing: enrolled roots become normal delivery relations

Bind a parent's fuzing enrollment to a particular CONFIG input contract. Within
each enrolled producer root, recognized paths/filenames become concrete source
relations. Feed those relations into existing copy/link input delivery; assemble
the resulting parent material through its normal CONFIG.

The new work is recognition and relation binding, not another merger. Inspection,
delivery, and assembly agree on selection. Copy refresh remains explicit; disabled
enrollment excludes retained material without requiring pruning. Qualified source
identities keep two members' identically named files distinct.

Start with native JSON or concat inputs so this landing can be proven without
coupling it to ENV quoting or interactive-shell policy. It should demonstrate:
one enrolled root, recognized material, parent input link/copy, and correct native
assembly; a second recognized file requires no additional per-file descriptor.

## Then ENV and the OpenCode use case

1. Give ENV ordinary CONFIG inputs under `etc/env.d/`. Resolve authored values
   once, excluding implicit execution-context variables from contributions.
2. Add the ENV processor/projections at CONFIG's existing processor seam. Settle
   precedence and literal serialization using the contract's cases.
3. Have systemd select env contribution files; have ZIM consume the intended
   application env contribution using its normal module mechanism.
4. Enroll OpenCode/proxy material and connect existing native configuration
   operations to the lifecycle at explicit points.
5. Prove existing-pane activation separately from on-disk assembly. ENV-to-ZIM
   dependencies use explicit sequencing until a candidate dependency feature is
   justified and implemented.

The architectural fork to avoid is requiring all of these concerns to land as
one generic engine. Multi-CONFIG packaging is useful on its own; native fuzing
delivery is useful with existing formats; ENV and shell activation can then be
developed against those concrete interfaces.

## Connections and constraints

- [Current contract](contract1.gpt6a.md) supplies intended membership/material
  semantics; this document narrows the implementation route and proof boundaries.
- [Earlier repeatable-generation work](/.design/config-mcp/draft1.gpt56t.md#implementation-wave)
  independently identified the two-generator-call isolation test. Its command
  design predates the current fixed command surface; reuse the test principle.
- [Earlier config graph proposal](/.design/config-mcp/draft2.gpt56t.md#config-graph-and-runtime-artifacts)
  includes explicit artifact dependencies. That is a possible later extension,
  not a prerequisite for independently instantiating current CONFIG.
- [Simplification plan](/doc/config/simplification.md#2-stop-emitting-an-old-command-model-and-rewriting-it)
  records the deletion of compiler path-rewriting layers. Generate each selected
  binding directly; do not revive emit-then-rewrite as the multi-instance strategy.
