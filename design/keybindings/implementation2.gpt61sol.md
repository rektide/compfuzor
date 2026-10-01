---
type: ArchitecturalCheckpoint
title: Declaration-driven producer installation and durable membership
description: General actions/bindings now package automatically and install through generated scoped entries with durable closed membership, with isolated proof and a gated Vicinae proposal.
resource: /design/keybindings/implementation2.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - resource: /design/keybindings/implementation1.gpt61sol.md
    title: Accepted bounded consumer/commit seam
  - resource: /doc/config/keybinding-producers.md
    title: Author-facing declarations and installation contract
  - resource: /tests/integration/keybindings_generated.test.py
    title: Stock rendered installation proof
  - resource: /design/keybindings/vicinae-proposal0.gpt61sol.md
    title: Proposed cutover values, not applied
---

# Outcome and scope

The parent asked for the central author-facing promise: named action/binding
declarations, automatic packaging and shared target installers, durable explicit
membership, and actual stock-worker installation proof—not another manual request
JSON exercise. **That path now exists.**

Producer playbooks author `KEYBINDING_ACTIONS` and `KEYBINDINGS`. Normal
`tasks/compfuzor.includes` synthesizes singular `action/<id>.yaml` and
`keybinding/<id>.yaml`, one closed producer manifest and user-scoped Niri/Umbriel
installer entries. A host declares consumer policy with familiar CONFIG
scope/root/subpath/selectors. No hand-authored per-binding ETC_FILES, CONFIGS or
BINS are required.

No live user configuration, Vicinae/KDE playbook, source-builder operation or
compositor reload was changed. The proposed client cutover is a separate document
and isolated executable fixture, awaiting parent review. Unrelated user/parent
changes remain excluded from these explicit-path commits.

# Saved stages

- `9339d9cf` — reject registration destinations that can alter another batch donor.
- `98969e91` — automatic resource packaging, stock worker reuse, durable membership
  and generated scoped target installers.
- `90ee6e32` — runtime consumer-profile selectors, author guide, stronger generated
  installation proof and isolated Vicinae proposal.

# Architecture and authority

| Concern | Implemented choice |
|---|---|
| Public producer authoring | `KEYBINDING_ACTIONS` and `KEYBINDINGS`, keyed by named IDs; the generator stamps version/kind/ID and rejects conflicting explicit values. Runtime YAML ID remains authoritative. |
| Producer membership identity | `KEYBINDING_PRODUCER`, default NAME, namespaces resource storage and membership groups. It does not rewrite action/binding IDs or pretend filename identity replaces record identity. |
| General target participation | `KEYBINDING_TARGETS` list or map selects known targets and explicit consumer/context/scope. Omitted ordinary producer targets generate both known user entries; there is no PATH discovery. |
| Consumer policy | `KEYBINDING_CONSUMERS` target profiles reuse CONFIG scope, named roots, subpath and env/default path selectors. Profile locators can be system paths or runtime HOME/XDG/env selectors. Packaged producer paths stay separate system paths. |
| Existing infrastructure | The existing CONFIG compiler exposes the same stock runner/processor bin records to domain hosts. No fake empty recipe or another transaction is introduced. Existing ordinary CONFIG deployments continue their own compilation path. |
| Aggregation | Normal `gen_bins` creates scoped aggregates; each target leaf participates exactly once. Authored system/user install bodies remain intact. New target leaves have `run: false`; render is not installation. |
| Closed membership | `.keybindings/membership.json` lists exact group/resource paths, identities, enabled state and order. Registered files live under `.keybindings/source/<producer>/<kind>/`; no directory scans infer source membership. |
| Ordering | Producer order then producer ID; ordered consumer user sources follow. Native source order uses the existing material interface. |
| Reinstall | Refresh managed YAML registrations (copy or link) as an explicit producer operation; preserve disabled slots and group enabled state. Native placements independently default to seed/preserve; refresh is explicit. |
| Smaller declarations | Replace only that group's declared resource list. Stale physical files remain excluded; no automatic pruning. |
| Metadata acceptance | Membership is a supplemental single-output recipe of the SAME CONFIG transaction as native outputs/root. Registration callback runs once; failure restores registrations and does not accept membership ahead of outputs. |
| Consumer-owned patches | Host declarations become its late user layer when no producer targets are explicitly declared. `patch: true` records are `whenPresent`: dormant while the base is absent/disabled. Strict core composition is unchanged for unconditional patches. |
| Native files | Same explicit ID/path/format/order/placement/incorporation interface; declared source registration disabled convention is preserved. |

The source-YAML versus native-copy distinction is intentional and documented.
Managed declaration copies are refreshed on producer reinstall so updated commands
reach canonical definitions. Editable native copies are not silently regenerated;
they retain user edits even while linked material tracks changed commands.

# Code references

- [Controller generator](/library/filter_plugins/keybindings_compile.py): thin
  packaging, consumer selector normalization and BINS synthesis, not domain
  composition/rendering.
- [Generator task](/tasks/compfuzor/gen_keybindings.tasks) and
  [normal task entry](/tasks/compfuzor.includes): declarations join the existing
  artifact and bin-composition pipeline.
- [Stock CONFIG records](/library/filter_plugins/config_compile.py),
  `config_runtime_bins`: reused exact worker artifacts, with render-time run
  disabled on the new domain bootstrap path.
- [Membership runtime](/files/config/keybindings/membership.ts): profile binding,
  closed state, deterministic source selection, authoritative record checks,
  upsert/enable/disable and one coherent registration callback.
- [Consumer supplemental outputs](/files/config/keybindings/consumer.ts): metadata
  participates in the already accepted CONFIG commit boundary and guard set.
- [Registration preflight](/files/config/registration.ts): cross-record destination
  versus donor chain checks, not merely each record versus its own source.
- [Installed CLI](/files/config/keybindings/runtime.ts): `install`, `host`,
  `enable`, `disable`, explicit profile selectors/context/scope and retained
  lower-level processor/consumer operations.

# Author-facing examples

Producer:

```yaml
KEYBINDING_ACTIONS:
  terminal-open: {exec: [foot]}
KEYBINDINGS:
  terminal-open:
    action: terminal-open
    keys: [Mod+Return]
    umbriel: {add-keys: [Alt+Return]}
KEYBINDING_TARGETS:
  niri: {consumer: /opt/desktop, context: user, scope: user}
  umbriel:
    consumer: "${XDG_CONFIG_HOME}/umbriel/keybinding-umbriel.json"
    context: user
    scope: user
```

Host/user policy:

```yaml
KEYBINDING_CONSUMERS:
  niri:
    contexts:
      user: {scope: user, root: config, subpath: niri}
    baseline: [/absolute/niri-baseline.kdl]
    personal: [personal.kdl]
    registration: copy
    placement: copy
    native_sources:
      - {id: own, path: own.kdl, order: 9000, placement: direct}
KEYBINDINGS:
  terminal-open:
    patch: true
    niri: {keys: [Alt+Return]}
```

The human runs the generated producer `bin/install-user.sh` or a selected target
entry. The host can explicitly reassemble or enable/disable a named group using
its runtime. It does not maintain per-application native include names or write
a low-level consumer request JSON.

# Actual proof, not fixture-only leaf setup

[Generated integration proof](/tests/integration/keybindings_generated.test.py)
renders through the real generator, filesystem writer, `gen_bins`, and stock
CONFIG/BINS tasks. The copied runner is byte-identical to `files/config-run.sh`;
its shared concat wrapper and omnibus runtime are generated artifacts, not manual
test leaves. The fixture declares its own system/user install bodies to verify
composition preservation.

The proof passed these scenarios:

1. Render host and two independent producers without running target installers.
2. Run complete generated user aggregates into stock isolated HOME/XDG contexts.
   Each target leaf appears once in aggregation; authored user body executes once.
3. Apply a host-owned chord patch without repeating a command, and include a
   user-owned native source plus late personal files.
4. Copy+include for Niri and link+include for Umbriel; refresh managed YAML copies
   on reinstall, retain edited native copy, track linked command change.
5. Reinstall smaller declarations: membership excludes the removed binding,
   root block disappears, stale physical source file remains.
6. Reject invalid native proposal during reinstall: root and membership bytes
   remain unchanged, managed copied YAML registration is restored.
7. Disable a contribution durably and preserve disabled state on reinstall;
   user patch becomes dormant rather than reactivating the producer.
8. Preserve a disabled resource slot during producer update, without duplicate
   blocks or source discovery from stale files.

The donor-collision unit test covers direct and symlink-chain cross-record
collisions before mutation. The proposal integration test renders the actual
Vicinae example with stock workers and verifies all requested chord outcomes.

# Verification

Passed:

- `python tests/integration/keybindings_generated.test.py` — full generated proof,
  including authored install bodies and disabled slots.
- `python tests/integration/keybindings_vicinae_proposal.test.py` — exact isolated
  proposed values, native validation, no application execution.
- `pnpm exec vitest run tests/config-keybindings` — **26 tests, five files passed**.
- New compiler tests and existing CONFIG compiler checks, syntax-check of the
  normal Vicinae playbook after adding the gated generator include.
- Build, typecheck, targeted lint/format and local-link checks.

Background independent follow-up review was attempted but blocked by the child
session depth limit. The parent's architectural review remains the review gate;
no independent-review result is claimed.

# Next gate: minimal client adoption, not another mechanism

Read [Vicinae/Umbriel proposal](/design/keybindings/vicinae-proposal0.gpt61sol.md)
and [declaration fixture](/examples/keybindings/vicinae.yaml) before authorizing
actual playbook changes. It preserves:

- Niri launcher `Mod+D`, clipboard `Alt+Grave`, windows `Mod+F`.
- Umbriel launcher `Mod+Space`, windows `Mod+Slash`, local clipboard `Mod+Grave`.
- Existing intentional open-versus-toggle behavior using verified modern
  `vicinae://launch/...` provider/entrypoint routes.
- KDE and source-builder/system installer bodies unchanged.

The real Niri consumer profile binding still needs selection/adoption. The
maintained Umbriel root needs deliberate array-area adoption and a seed writer
policy so render does not erase managed blocks. Those are proposed, not applied.

Remaining boundaries are unchanged: no live deployment/reload, no automatic
pruning, no Effect implementation, no crash-atomic registration/output transaction,
and no isolation from concurrent external assemblers. State guards detect observed
changes but do not remove the final check-to-commit race.

# Cross-references

- [Producer guide](/doc/config/keybinding-producers.md): maintained author entry
  point, selector conventions and distinct source/material update policies.
- [Consumer guide](/doc/config/keybinding-consumers.md) and
  [accepted prior checkpoint](/design/keybindings/implementation1.gpt61sol.md):
  reused publication/root-adoption architecture, not a second executor.
- [Vicinae proposal](/design/keybindings/vicinae-proposal0.gpt61sol.md): exact
  application values, primary-source URI evidence and unresolved live adoption gate.
- [Mise2](/mise2.opt.pb) and [Zim2](/zim2.opt.pb): concrete context, block placement,
  scoped aggregation and installation-owner precedents retained by this design.
