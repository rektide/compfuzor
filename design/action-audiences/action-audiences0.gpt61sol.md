---
type: DesignSynthesis
title: General action aliases over existing context-aware operations
description: Proposed seam for user-first action defaults, explicit audience aliases and reusable CONFIG operations, with placement and availability kept distinct.
resource: /design/action-audiences/action-audiences0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-06 }
verified: { by: unverified }
sources:
  - resource: /design/action-audiences/intent0.gpt61sol.md
    title: Operator direction and corrected interpretation
  - resource: /design/action-audiences/config-stages0.gpt61sol.md
    title: Existing CONFIG stage and commit contracts
  - resource: /design/action-audiences/action-variants0.gpt61sol.md
    title: Existing alias precedents and native .mts probe
---

# Situation

Both research tracks support the operator's recollection: context-selecting
symlink installers and separate CONFIG operations already exist. The missing
work is **generalization and integration**, not inventing a parallel assembly
system or making USERMODE change more globals.

This is a proposed shape for review, not an accepted schema or implementation
plan. Existing USERMODE and live installations remain unchanged.

# One action executable, explicit audience aliases

The requested user-default family can be represented as:

```text
assemble-user.mts       # real executable; real filename indicates default
assemble.mts        → assemble-user.mts
assemble-system.mts → assemble-user.mts
```

The system-default family reverses which qualified filename is real. A native
`.mts` scratch probe verified the user-default form on Node 26; shell Zim
installers provide existing production precedent for preserving alias identity.

The shared invocation module should retain three independent facts:

1. **Invoked spelling:** selects the action and any explicit audience.
2. **Physical executable:** establishes implementation identity, deployment
   rooting and the default audience encoded in its qualified filename.
3. **Declared availability:** determines whether the selected operation is
   permitted and has a usable audience/context plan.

Only the first fact should choose an explicitly qualified audience. Resolving
all names to the physical filename before selection would erase the override.
Existing flow containment checks already preserve this distinction.

One executable does **not** require identical user and system effects. The
executable selects an audience-specific plan: user versus system systemd manager,
different consumer contexts/roots, and potentially different declared leaves.
The implementation can share machinery while preserving those differences.

# Reuse the operations that already landed

| Operator intent | Existing operation to reuse |
|---|---|
| Assemble configuration for a receiver | CONFIG context-bound recipe assembly, native/transaction validation and output commit |
| Deliver existing assembled output by copying or linking | CONFIG publication with copy/link strategy |
| Seed editable/linked inputs and build receiver output | CONFIG assemble-style installation |
| Observe or update input contributions | CONFIG input operations and registration machinery |
| Complete installation including activation | Domain installation plan, e.g. Zim's loaders/caches/wiring after CONFIG assembly |

This can support a small general public action vocabulary without exposing
`keybindings.mjs` as the normal operator command. Domain-specific preparation
still earns its place internally; it should contribute work behind the common
interface, not be deleted merely because it has a domain name.

Two seams need deliberate treatment:

- **Generic aggregate versus domain operation.** Today's `config.sh`
  configuration-generator aggregate and `config-assemble.sh` runtime operation
  are distinct. A bare `assemble` action should say whether it aggregates
  declared assembly contributions, executes one domain operation, or supports
  both through one declared action plan. Prefix matching alone is insufficient.
- **Shared transaction versus sequential operations.** A general action may
  aggregate complete operations sequentially, but this does not make their
  mutations one transaction. For keybindings to share CONFIG's candidate set
  with other recipes, expose its preparation result rather than nesting its
  already-committing consumer operation inside a leaf processor.

# Policy dimensions to keep independent

The eventual interface needs three policy choices without an action-by-context
wrapper matrix:

1. **Default audience:** user for the new mode; existing behavior may require
   compatibility during adoption.
2. **Availability:** supported audiences per action, including omitting install
   while assembly/status remain available.
3. **Placement and delivery:** home-local or shared deployment material;
   invocation-time receiver contexts; copy/link/assembly strategies.

No final variable names are proposed yet. Existing declared contexts may have
names other than `user` and `system`; audience selection needs a mapping to
those contexts, not a rule that erases them.

An explicitly selected unavailable audience should fail clearly rather than
fall back to the default and mutate a different receiver. This guard is useful
even if an old alias remains on disk: ordinary rendering should not gain broad
pruning behavior merely to enforce availability. Whether deliberate skip flags
mean omission or runtime no-op remains an operator decision.

The user asked for home-local installation. Selecting user scope cannot be
presented as resolving that placement concern while keeping all new deployment
material under `/etc/opt`. Define the desired local material root and how shared
producers discover it, without moving arbitrary existing material automatically.

# Open decisions before implementation

- **Runtime compatibility:** adopt native `.mts` with an appropriate minimum
  Node version, or retain built `.mjs` distribution support for the declared
  Node 20 lane? Workstation success is not the supported deployment contract.
- **Public naming/composition:** how should general `assemble` and `publish`
  operations participate in the existing action catalog and shell aggregates?
- **Availability behavior:** omit unsupported aliases, explicit bypass/no-op,
  or both with separate meanings?
- **Default precedence:** keep the existing explicit option → alias → env →
  default selection, or make qualified audience aliases hard assertions?
- **Local material placement:** choose a durable local deployment layout that
  does not mingle source declarations and runtime executables accidentally with
  compositor receiver files.

# Proposed next checkpoint

First exercise the **shared invocation and alias-family seam** with both
defaults, disabled audiences, lexical-path preservation and source/built
execution. Then connect an existing CONFIG action and one mixed-audience
installation plan. This tests the generic abstraction against two genuinely
different uses before integrating keybindings preparation or changing live
material placement. No broad USERMODE replacement or live migration should be
authorized implicitly by that prototype.

# Cross-references

- [Intent](/design/action-audiences/intent0.gpt61sol.md): distinguishes filename
  retirement from the user's default-audience and home-local expectations.
- [CONFIG stages](/design/action-audiences/config-stages0.gpt61sol.md): supports
  reusing assembly and clarifies that assembly already commits outputs.
- [Action variants](/design/action-audiences/action-variants0.gpt61sol.md):
  supports alias selection and identifies missing generalization and packaging.
- [SteamOS deployment](/steamos-niri.opt.pb): concrete mixed-audience plans
  (system provisioning versus user configuration) that should remain different
  behind one action implementation.
