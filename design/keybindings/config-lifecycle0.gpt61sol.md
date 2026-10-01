---
type: ArchitectureProposal
title: Named actions and keybindings through the CONFIG and CFR lifecycle
description: Deploy typed YAML contributions, compose named actions and invokers, and assemble and publish target-specific artifact sets through native CFR configuration workflows.
resource: /design/keybindings/config-lifecycle0.gpt61sol.md
tags: [config, cfr, keybindings, actions, niri, umbriel, contributions]
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - id: operator-direction
    resource: /vicinae.src.pb
    title: Operator discussion and existing Vicinae contributions
  - id: cfr-direction
    resource: /design/compfuzor-runtime/effect-draft2.gpt6a.md
    title: Native Effect contributions and collaborative runtime pipelines
  - id: config-implementation
    resource: /library/filter_plugins/config_compile.py
    title: Current controller-side CONFIG compilation
  - id: retained-contributions
    resource: /design/compfuzor-runtime/firmament-candidates0.gpt6a.md
    title: Retained sources and attributable composition candidates
---

# Situation and destination

Vicinae currently authors Niri KDL, Umbriel TOML, and per-target shell installers.
The desired interface declares named actions independently from the bindings
that invoke them. `niri:` and `umbriel:` contributions can refine either side:
override a default, add another binding, or supply native target behavior. KDE
is excluded from this work; its existing implementation is left untouched.

The operator wants automatic generation of target installers and explicitly
invites adaptation of CONFIG toward the actively rebuilding CFR. Zim2/Mise2
provide experimental assembly examples, not stable interfaces to freeze.

**Destination:** scripts/actions and keybindings are typed source configurations.
Their YAML survives deployment. Native configuration workflows collect and
compose those inputs, render target artifact sets, validate candidates, and
publish them. Generated installers enter those workflows; they do not contain
another implementation of composition.

Research prompt: how can two independently contributed source configurations
feed named, target-specific configuration workflows while preserving raw inputs,
mutable collaboration, provenance, multi-artifact validation, and compatibility
with current CONFIG transactions?

# What exists, and what does not

| Evidence | Consequence |
|---|---|
| [`config_compile.py`](/library/filter_plugins/config_compile.py#L16-L18) hardcodes `concat`, `json-deep-merge`, and `block-in-file`. Its output loop is filename-keyed and each recipe has one output. | Neither YAML decoding nor typed action/binding composition exists. A native artifact-set interface is new work, not another spelling of an existing processor. |
| [`sub_config.tasks`](/tasks/compfuzor/sub_config.tasks) compiles declarations; [`gen_config.tasks`](/tasks/compfuzor/gen_config.tasks) merges compiled contributions. | Keep packaging/synthesis separate from runtime configuration semantics. Do not grow `gen_config.tasks` into a second renderer/interpreter. |
| [`fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks#L166-L172) supports `ETC_FILES.yaml`. | Shipping resolved declarations as YAML already has a filesystem materialization path. It does not imply preserving original YAML comments or controller-side Jinja expressions. |
| [`assembly.ts`](/files/config/assembly.ts) invokes [`config-run.sh`](/files/config-run.sh), which builds, validates, and commits selected outputs. | Legacy assembly is a complete mutation, not a prepare-only Activity. Initially admit it opaquely rather than execute it and then publish the same outputs again. |
| [`publication.ts`](/files/config/publication.ts) publishes outputs individually. | This is not an existing multi-artifact publication transaction. Delivery primitives can be reused, but bundle validation and rollback need their own explicit implementation. |
| [`config-remote/runtime.ts`](/files/config-remote/runtime.ts#L124-L146) puts a symlink and rebuilds, restoring the previous link on failure. | Registration plus rebuild already has useful transactional precedent. Keep its legacy operation intact; do not independently register actions and bindings and expose an invalid intermediate graph. |
| [CFR draft2](/design/compfuzor-runtime/effect-draft2.gpt6a.md) describes native Activities/Workflows, extensible init, mutable run data, staged collection, and durable history. | These are the destination contracts, not shipped APIs. The Effect scratch probe does not prove draft2's discovery, invocation binding, history, or deployed dependency delivery. |

# 1. Package declarations, not prematurely flattened target text

For this proposal, **package** means materialize the declared resources and the
runtime contributions needed to interpret them in the deployment. It does not
mean an npm build, an archive format, or live consumer installation.

Illustrative producer layout:

```text
<vicinae deployment>/etc/config/
  actions.yaml
  keybindings.yaml
```

These are two separately named, versioned configuration resources. They may
travel in one registration operation because bindings reference actions. The
existing CONFIG spec or its successor records their kinds, names, source paths,
and provenance; no redundant universal material catalog is required.

The action resource describes command/script behavior; the binding resource
describes named invokers and their target refinements. Neither is a native CFR
module, an Effect closure serialized as YAML, or an instruction language for the
CFR execution engine.

Resolve controller-only Jinja values at packaging time. Retain runtime path/env
selectors explicitly; do not indiscriminately envsubst command strings. Inline
script bodies are trusted executable material, not inert/sandboxed configuration.
Keep `exec` argv distinct from explicit shell/script bodies.

Generators are thin adapters from authoring variables to source resources and
configuration participation. Admit their declarations before CONFIG compilation
when they extend `CONFIGS`; the current include sequence compiles CONFIG before
some domain generators. Avoid implementing effective merge semantics twice in
Python and TypeScript.

# 2. Admit typed configurations through an extensible native seam

CONFIG needs to distinguish a logical configuration from one output filename:

- **Source configurations:** named actions/scripts and named bindings.
- **Derived configurations:** executable action material and Niri/Umbriel
  projections of the selected source configurations.
- **Consumer bindings:** explicit user/context roots, baseline configuration,
  selected contributors, override order, and installation representation.

The native CONFIG interface accepts captured typed sources and context settings
and returns a candidate artifact set. An artifact set is a bounded delivery
contract, not a general workflow AST: paths, bytes or candidate references, modes,
relationships, and validation evidence. Execution remains authored Effect work.

Domain-group implementation, provisionally:

```text
files/config/                 # capture, source inventory, lifecycle, delivery
files/actions/                # command/script decoding and executable rendering
files/keybindings/            # binding composition and action reference checks
files/compositors/niri/        # native projection, assembly, validation
files/compositors/umbriel/     # native projection, include-chain assembly, validation
```

Each domain provides its schemas/reducers and annotated native lifecycle exports.
New configuration kinds must not require adding a member to a central union of
all compositor settings or another hardcoded shell processor branch. Shared
field/schema identities and contribution annotations follow CFR's admission
contract; domain modules do not register themselves by top-level side effect.

Legacy filename recipes remain supported through their existing adapter. The new
source/derived configuration interface need not pretend `config.spec` version 2
already supports multi-output plans; version its extension deliberately.

# 3. Collect sources and compose meaning before rendering

A selected consumer context holds explicit registrations for packaged resources.
Generated contributor installers bind the producer, context, and target and
request registration plus configuration deployment. No human adds every app's
filename to `umbriel.user.pb`, and no directory scan of all machine deployments
is required to discover willing producers.

Automatic installer generation does not imply installing into every compositor
found on PATH. Target membership/selection is declared policy. Niri and Umbriel
can have built-in user defaults, with an explicitly bound consumer deployment
overriding them; a running compositor is not necessary for offline installation.

Capture the selected YAML once for the run, retaining individual source records,
identities, content revisions, and provenance. Both targets consume that capture
when their source selections match. Different selections have different bindings;
shared capture does not mean shared effective settings.

Composition resolves:

```text
producer actions and suggested bindings
  + additional registered contributions
  + niri:/umbriel: refinements
  + consumer/user policy
  -> resolved named actions and binding invocations for this target
```

Choose field-specific rules: `exec` replaces as a complete argv; script bodies
replace; default chords may be replaced; additional chords union deliberately;
native property mappings merge under defined rules. Do not concatenate arbitrary
arrays or silently append arguments to an overridden command. A named binding
may reference an action contributed by a different source.

Keep source contributions instead of only a flattened winner. Disabling a source
can reveal a lower-priority value. Intentional patches/overrides are allowed;
accidental conflicting definitions need an explanation or an error. Validate
unresolved action references, cycles if introduced, and effective chord conflicts
with target-aware key normalization. A native implementation can be target-only;
do not invent a shell equivalent for a compositor-only action.

# 4. Assemble executable material and native invokers

Common command/script actions can yield stable executable entry points. Bindings
refer to those artifacts rather than duplicating command bodies. An `exec` action
does not need a wrapper for correctness, but one gives reusable invocation and a
stable named artifact. Decide wrapper use as a renderer policy, not a prerequisite
for every action. Target-refined commands require target-qualified artifacts;
they cannot overwrite a supposedly shared script with different content.

Native compositor actions render directly as native invocations. This distinction
preserves future menus, desktop launchers, or other invoker adapters without
promising all compositor-only actions work outside their compositor.

**Keypresses do not run configuration Workflows.** Normally they execute the
published command/script or native compositor action. CFR prepares/deploys that
material and can inspect it; it is not a required daemon or YAML interpreter on
the hotkey path. Domain action identity and CFR lifecycle Activity identity remain
distinct even if an explicit future runtime command exposes named action execution.

Niri can assemble `//`-marked blocks containing complete `binds` sections or
include declarations. Upstream later `binds` sections override matching chords;
duplicates within one section are errors.

Umbriel generates separate TOML fragments and one ordered include chain, with
the installed baseline first and personal overrides last. Multiple `[keybinds]`
tables cannot be text-concatenated into one TOML file. Use block-in-file to own
text placement, not to pretend TOML table composition is a text operation. An
existing unmanaged include table needs an explicit adoption/structured-edit policy;
never append a second `[include]` or silently overwrite the user's root.

Capture the existing consumer root as an input when preserving unmanaged text.
Validators must inspect the complete staged layout, including relative include
resolution and executable references. Validating a temporary root whose includes
resolve to old live fragments is not validation of the candidate bundle.

# 5. CFR owns the lifecycle, not the keybinding language

Proposed workflow; names below describe responsibilities, not existing APIs:

```text
shared init: explicit deployment/consumer/user binding and environment
  -> capture registered configuration sources and existing consumer state
  -> contributed adjustments to settings/source selection
  -> snapshot effective inputs for target assembly
  -> compose actions/bindings and produce candidate artifact sets
  -> validate every selected candidate
  -> deploy declared artifacts and commit registration changes
  -> optional explicit reload
```

The CONFIG parent can use all-assembly-before-publication stage barriers for
selected Niri/Umbriel configurations. A standalone target installer enters the
same target workflow. Nested workflows join the initialized workspace rather
than resetting it. Generated shell entries are projections of those bindings,
not independent executors or handwritten target logic.

Resources live in schema-backed run fields such as `ConfigInputs(consumer,
config)` and `ConfigSettings(consumer, config)`, with candidate sets in a derived
field. A loader's captured result feeds a workflow-level state update, so reused
Activity results still reconstruct state. Do not hide essential writes solely
inside an Activity body that Effect may skip on replay.

The same assembler definition bound to Niri and Umbriel needs distinct invocation
occurrences. Otherwise Activity result identity can accidentally reuse one
target's output for the other. Bind source revision, target, effective settings,
and implementation identity; record source/member selection and output evidence.

Native contributions can adjust run data before an explicit collection/snapshot
point. Reads do not create scheduling edges automatically. No reactive graph,
watch daemon, or second recipe interpreter is required for this finite workflow.

Publishing scripts, fragments, and roots is a new multi-artifact concern. Validate
all first, then publish dependencies before root entry points, preserving rollback
for ordinary failures. Detect changed roots/registrations before overwriting a
stale snapshot. Define locking, symlink policy, modes, and interruption behavior.
Do not advertise crash-atomic multi-file delivery or exactly-once host mutation.
Preserve old valid consumer configurations on preparation/validation failure.

Registration plus deployment is one outer operation. If deployment fails, restore
registration. Do not inherit `config-remote`'s coupled rebuild and also run a
second native assembly. Initially keep legacy operations opaque; extract them
only when the corresponding transaction is preserved.

History records the managed configuration operation and its source/target binding,
not future compositor keypresses. Durable history is distinct from cross-process
Workflow resume. The latter requires retained inputs, reconstructible handler
dependencies, and engine persistence; it is not proved by saving YAML or logs.

# 6. Coherent implementation checkpoints

1. **Typed resources and reducers.** Package Vicinae actions and bindings as two
   YAML resources; decode, compose, explain, and render candidates in isolation.
   Prove cross-source action references, target extensions, script quoting, native
   actions, and source disabling. No live consumer writes yet.
2. **Minimal native lifecycle.** Use CFR's common discovery/init/binding/history
   machinery for one configuration workflow. Prove contributions can adjust a
   captured field before assembly; bind the same definition to two targets without
   result collision; demonstrate execution from a deployment outside repo tooling.
   Preserve unrelated BINS/CONFIG behavior; do not wait for a universal rewrite.
3. **Artifact-set deployment and generated installers.** Register both resources
   together; assemble and validate staged Niri/Umbriel layouts; publish through
   shared delivery. Auto-generate installer participation, preserving user scope
   and configured target selection. Test failure rollback and root edit conflicts.
4. **Vicinae cutover.** Replace only its handwritten Niri/Umbriel material and
   installers after behavior parity. Preserve intentional target chord differences;
   add shared clipboard history. Adapt Umbriel user configuration's baseline/local
   policy without hardcoding producer names. Leave source builds and KDE unchanged.
5. **Second contributor.** Use Handy or a small terminal launcher contribution to
   prove the seam. It must need declarations, not a new CONFIG branch or custom
   installer. Reuse legacy Zim/Mise operations opaquely and migrate their internals
   only in separately justified work.

Commit each coherent checkpoint. Before live deployment review the interfaces,
actual candidate layout, source-selection policy, and transaction evidence.

Acceptance scenario: package Vicinae; generate both target installer bindings;
register into an isolated consumer context; override only one chord in user YAML;
assemble both projections; publish and validate; change the action command and
reassemble without editing bindings; disable a source and explain the resulting
effective configuration; reject malformed YAML/unresolved actions without changing
the installed configuration. Stale files are not automatically pruned or admitted
as undeclared resources. Managed block replacement remains explicit configuration
assembly, not general filesystem reconciliation.

# Cross-references

- [CFR native draft2](/design/compfuzor-runtime/effect-draft2.gpt6a.md): execution
  authority, native discovery, mutable init, target-qualified occurrences, and
  history; this proposal is a concrete configuration application of that direction.
- [Firmament candidates](/design/compfuzor-runtime/firmament-candidates0.gpt6a.md):
  retained source contributions, field-specific merge rules, captured projections,
  and value versus occurrence identity. Recommendations remain inquiry, not an
  accepted requirement to implement Firmament's live engine.
- [Consumer toolkit](/doc/config/consumer-toolkit.md): current copy/link/assemble,
  context, input toggling, bypass, and safe-delivery semantics to preserve where
  applicable; it does not yet document this typed/multi-artifact interface.
- [CONFIG README](/doc/config/README.md): distinguishes fixed CONFIG commands from
  the generic config compositor lane; generated target entries should share a
  lifecycle implementation rather than conflate those names.
- [Vicinae playbook](/vicinae.src.pb): concrete duplicated source/install logic and
  intentional chord differences to migrate; existing KDE remains outside scope.
- [Umbriel user playbook](/umbriel.user.pb) and [root template](/files/umbriel/config.toml):
  baseline preservation, one include table, and late local overrides. Automatic
  contribution collection removes the need to hardcode application filenames.
- [Niri config decoder](https://github.com/niri-wm/niri/blob/main/niri-config/src/lib.rs#L218-L230):
  independent binding sections override chord-by-chord; supports structured section
  assembly, not arbitrary duplicate keys inside one section.
- [Umbriel include merge](https://github.com/noctalia-dev/umbriel/blob/main/src/config/config_merge.cpp#L303-L340):
  included files merge in order and the including file wins last. Target assembly
  must preserve this meaning and validate against the full candidate layout.
