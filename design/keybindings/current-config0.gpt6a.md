---
type: ArchitectureProposal
title: Prove named actions and bindings through the current CONFIG seam
description: Extend the existing single-output processor protocol, retain YAML contributions, and carry the same domain implementation into CFR draft2 as a versatility test.
resource: /design/keybindings/current-config0.gpt6a.md
status: draft
generated: { by: model:gpt6a, at: 2026-10-01 }
verified: { by: unverified }
tags: [config, keybindings, niri, umbriel, cfr]
sources:
  - id: predecessor
    resource: /design/keybindings/config-lifecycle0.gpt61sol.md
    title: Earlier typed configuration lifecycle proposal
  - id: existing-compiler
    resource: /library/filter_plugins/config_compile.py
    title: Current CONFIG compilation
  - id: existing-runner
    resource: /files/config-run.sh
    title: Existing single-output candidate and transaction protocol
  - id: cfr-direction
    resource: /design/compfuzor-runtime/effect-draft2.gpt6a.md
    title: Native Effect contributions and collaborative runtime pipelines
stale_after: 2026-11-01
---

# Revision and agreement to seek

The operator challenges the earlier proposal's prerequisite CONFIG redesign.
Prove the named action/binding model with the current system first; then use that
working implementation to test whether CFR draft2 is versatile and extensible
enough to host it. This proposal replaces the earlier implementation order, not
the named action/binding contract.

**Keep filename-keyed CONFIG recipes and the existing transaction runner. Add a
supported external processor seam, and implement actions/bindings as domain code
behind it.** No multi-artifact recipe interface or CONFIG dependency scheduler
is required for the first version.

# The module we build

An importable domain module performs:

```text
decode typed YAML contributions
  -> compose named actions and named bindings for a target
  -> resolve action references and validate effective invocations
  -> render one complete target keybinding fragment
```

Inputs are captured documents with source identity/order, target, and target
settings. Results include effective named records, provenance/diagnostics, and
rendered bytes. Pure composition/rendering does not read files, write output,
discover sources, or inspect ambient environment. These are real internal seams,
not a serialized workflow language.

Actions and bindings remain distinct configurations at the domain interface.
They need not become separately assembled intermediate files. Both can be inputs
to a single current CONFIG recipe; this avoids reading stale intermediate outputs
or requiring a new dependency engine.

Niri and Umbriel serializers consume the same resolved invocation model while
retaining target-native actions and options. Shared field rules include complete
argv replacement, explicit chord replacement/addition, intentional named patches,
and source-level provenance. Native chord equivalence belongs to target adapters.

# Small generic CONFIG extension

Today the compiler admits three fixed processor names, and the runner already
calls an executable leaf with `--config NAME`, `CONFIG_SPEC`, `CONFIG_INPUTS_FILE`,
`CONFIG_CANDIDATE`, and `CONFIG_TRANSACTION`.

Allow a recipe to select a deployed processor executable plus fixed argv as an
alternative to the existing built-in processor names. Validate the declaration;
generate the leaf through normal BINS synthesis with correct argv quoting. The
external processor gets the same contract and writes only its one candidate.
It does not publish, reenter CONFIG, or mutate registrations. Unknown processors
still fail rather than guessing a command from a string.

Illustrative, unsettled authoring syntax:

```yaml
CONFIGS:
  keybindings.kdl:
    name: niri-keybindings
    processor:
      command: config/keybindings
      args: [--target, niri]
    inputs:
      - glob: contributions/*.yaml
        name: desktop-inputs
      - file: policy.yaml
```

Each input YAML carries a kind/version and named records, so actions and bindings
can share an ordered input collection without inferring semantics from filenames.
Separate action/binding files are supported; a packaging envelope containing both
could be considered later without changing their logical separation.

The runner still owns enumeration, candidate creation, validation, check/stdout,
commit, and rollback. The current per-file manifest is not a content snapshot:
this version does not claim all target recipes read an identical source revision.
The domain adapter captures its own inputs before reduction. CFR can later supply
one shared capture to multiple targets without changing that reducer.

# Producer and consumer configuration

Vicinae declares actions and bindings once. Thin generators package the YAML and
beget user-scoped Niri/Umbriel installer entries. Those entries delegate to shared
target installer code with explicit producer and consumer/context bindings.

Consumer recipes are ordinary CONFIG recipes producing:

- Niri: one generated KDL fragment containing resolved bindings.
- Umbriel: one generated TOML fragment containing one `[keybinds]` table.

An arbitrary number of contributor sources feed each aggregate fragment. The
consumer root needs one managed inclusion, not a list of every contributor.
Niri's root can use a `//` block-in-file include. Umbriel's existing root includes
the baseline, the aggregate fragment, and personal overrides in that order.
Umbriel root adoption/editing remains target-specific: never append a duplicate
`[include]` table to an arbitrary user's TOML.

Registering a producer's two resources should be one bounded operation with
backup/rollback, followed by one target assembly. Do not issue two current
`config-remote put` calls: each rebuilds immediately and would expose a half-added
action/binding pair. Reuse input/link delivery primitives, with a shared batch
helper; preserve existing disabled registrations. This helper can remain a domain
installer operation until another consumer justifies a general batch interface.

Installing into a missing target consumer needs defined bootstrap behavior:
generated defaults can create the consumer recipe/state in an explicit user
location. Existing user deployment configuration overrides those defaults.
No running compositor or global scan is required. Generation of both installers
and participation in broad install aggregates remain separate policy decisions.

Root activation follows successful assembly and whole-consumer validation. On
updates, validate a temporary candidate root/layout referencing the candidate
fragment before replacing an already active fragment. Preserve unrelated root
text, resolve relative includes correctly, and serialize/check concurrent edits
at the installer seam. This is target installer logic, not processor mutation.
Report the existing limitation honestly: there is no new crash-atomic transaction
across roots, fragments, and registrations.

# What happens to scripts?

The first version resolves named actions into native command invocations while
rendering bindings. Multiple invokers can refer to one declaration even if the
resulting target text repeats an argv. This is source-level independence without
requiring a new executable artifact for every action.

Explicit shell bodies can be rendered as explicit shell invocations; reusable
script files can already be supplied through BINS and referenced by actions.
Neither action bodies nor external commands execute during configuration assembly.

Independent generation of one executable per named action is an additional
output feature, not a reason to replace CONFIG's recipe contract now. If wanted
in this first version, make that decision explicitly and prove its output/mode
and publication needs separately. Current config-run defaults new files to 0600,
so pretending it already installs executable script outputs would be incorrect.

# How this tests draft2

There are two successive admissions of the same working feature:

1. CFR admits the complete generated target installer as a legacy BINS Activity.
   Its registration/assembly/activation behavior stays opaque and runs once.
2. Native CONFIG contributions import the same domain module. Capturing YAML is
   an Activity, composition/rendering consume captured values, and a native
   workflow owns target binding and delivery sequencing. Do not execute the old
   complete installer as well as its extracted native children.

Use the existing implementation as the behavioral oracle for native admission:
same sources and settings should yield the same effective actions, invocations,
rendered fragments, and conflict outcomes.

Draft2 then has concrete tests beyond output parity:

- discover an added configuration contribution without editing a central kind
  union or dispatch switch;
- let a native init contribution add/override a binding before assembly;
- bind one captured input selection to Niri and Umbriel with distinct invocation
  occurrences and isolated target settings;
- choose complete target pipelines or all-assembly-before-publication;
- reconstruct captured inputs and run-data updates correctly on result reuse;
- report actual source/member selection and outcomes in durable history;
- execute installed modules outside the authoring checkout.

These are CFR versatility tests, not grounds to introduce another executor in the
keybinding module. If native admission requires rewriting its semantic core,
investigate CFR's binding/service seam rather than automatically rewriting the
domain to fit it.

# Implementation order and review gates

1. Prove the external single-candidate processor contract, including failure,
   check/stdout, and existing built-in compatibility.
2. Package YAML and implement the domain module plus both target serializers.
   Use isolated consumer roots and native compositor validation.
3. Generate shared-installer bindings; prove registration batching, target root
   integration, user overrides, disabled sources, and update failure behavior.
4. Cut over Vicinae Niri/Umbriel contributions and prove a second contributor
   needs declarations only. KDE stays outside this slice.
5. Give the working example and acceptance fixtures to draft2: legacy admission
   first, then native participation and its stronger tests above.

Each gate is independently useful and committed. Confirm this narrower design
before implementing; the predecessor's multi-artifact CONFIG redesign is no
longer a prerequisite.

# Cross-references

- [Earlier lifecycle proposal](/design/keybindings/config-lifecycle0.gpt61sol.md):
  retains useful domain/lifecycle distinctions, but its proposed core CONFIG
  expansion is deferred by this smaller proof.
- [Current compiler](/library/filter_plugins/config_compile.py), [runner](/files/config-run.sh),
  and [assembly binding](/files/config/assembly.ts): existing executable-leaf
  seam and candidate transaction reused here.
- [Remote input installer](/files/config-remote/runtime.ts): reference for
  registration rollback and the reason to avoid repeated immediate-rebuild puts.
- [CFR draft2](/design/compfuzor-runtime/effect-draft2.gpt6a.md): intended native
  admission and collaboration semantics that this feature can validate.
