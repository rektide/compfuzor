---
type: ArchitecturalCheckpoint
title: First action and keybinding processor slice
description: Working pure TypeScript domain and current CONFIG adapter, with explicit per-binding definitions/incorporation and an installation gate.
resource: /design/keybindings/implementation0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - resource: /design/keybindings/current-config0.gpt6a.md
    title: Current CONFIG external-processor direction
  - resource: /doc/config/keybindings.md
    title: Implemented authoring and processor guide
  - resource: /tests/config-keybindings/processor.test.ts
    title: Context, deployed processor and native validation evidence
---

# Situation and gate

The operator asked for forward implementation, favoring TypeScript and the
Mise2/Zim2 CONFIG world rather than a prerequisite general runtime rewrite.
The parent retained architecture ownership and requested a first coherent
interface/processor/domain checkpoint before live deployment or broad Vicinae
cutover. **That slice is implemented and committed. No live compositor config,
source-builder playbook, Vicinae contribution, or KDE adapter was changed.**

User work, including the preexisting `files/mise-cache.sh` deletion and unrelated
playbook edits/addition, was not included in these explicit-path commits.
Nested background delegation was attempted but blocked by the session depth
limit; this implementation and its routine verification ran in the owning session.

# Saved stages

1. `70972327` — **Support deployed external CONFIG processors with fixed argv**.
   [Compiler](/library/filter_plugins/config_compile.py),
   [compiler tests](/tests/filter_plugins/config_compile.test.py),
   [runner protocol tests](/tests/integration/config_external_processor.test.py).
2. `507a36e0` — **Render named action and keybinding materials through TypeScript
   CONFIG processors**. Pure domain, processor adapter, existing-runtime alias,
   bundled YAML dependency, tests and [implementation guide](/doc/config/keybindings.md).

# Interface chosen and architectural choices

| Concern | Chosen interface and reason |
|---|---|
| Domain source | One `version: 1`, `kind: action` or `kind: keybinding`, named record per YAML file. Direct `action/<id>.yaml` / `keybinding/<id>.yaml` packaging through `ETC_FILES.yaml`; no aggregate envelope. |
| Independent action | Complete `exec` argv, explicit `{shell, body}` script, or target-native implementation. Bindings reference action identity; no executable wrapper generation. |
| Intentional user changes | `patch: true` explicitly modifies an earlier named declaration. Target refinement is resolved within each source layer, then user layers apply, so producer target defaults cannot hide user shared patches. |
| Array semantics | `exec` replaces completely. `keys` replaces all existing chords, including previous additions. `add-keys` is a deliberate union. No generic array merge. |
| Target options | Scalar option mappings merge by property name; use target specifiers for native spelling differences. Native option validation is not duplicated in a stale central whitelist. |
| Material identity | Definition `niri/<id>.binding.kdl` or `umbriel/<id>.binding.toml`; incorporation `niri/<id>.include.kdl` or `umbriel/<id>.include.toml.part`. Explicit material suffixes avoid collisions for IDs such as `launch.include`. |
| Incorporation | Niri include statement; Umbriel array entry, not standalone TOML. Include processor reads exactly one selected native input **path**, not its live bytes. Ordinary context input binding therefore controls the reference. |
| Current recipe expansion | Pure `projectionRecipes` expands captured inventory into separate filename-keyed single-output recipes, with distinct definition/include recipe names. This is available as an import; automatic producer registration/installer generation is not implemented yet. |
| Source interface | Pure `NativeSource` carries explicit ID/path/format/order and direct/copy/link placement. Generated definitions and authored native files use the same selection interface. Stable `blockIdentity` is contribution-based. |
| Root shape | A new skeleton renderer orders baseline, contributions, then personal references. One Umbriel `[include]` table; independent definitions remain independent. It is deliberately not an existing-root adoption editor. |
| Runtime admission | External processor declaration `{command, args}` extends the existing compiler only. Existing transaction runner owns publication; the TS adapter writes one candidate. Existing omnibus distribution carries the processor, including YAML, and works outside the checkout. |

Core references:

- [Decode](/files/config/keybindings/decode.ts): strict record/YAML admission;
  duplicate keys, multiple documents, custom tags and aliases are rejected.
- [Compose/resolve](/files/config/keybindings/model.ts): named graph, target
  refinements, intentional patches, complete argv replacement and chord ownership.
- [Native serialization](/files/config/keybindings/render.ts): Niri argv spawn,
  explicit shell invocation, target-native actions, Umbriel shell quoting, separate
  definition and reference material.
- [Material selection/root shape](/files/config/keybindings/materials.ts): explicit
  source membership, effective paths, order and stable contribution identity.
- [Recipe expansion](/files/config/keybindings/recipes.ts): many current recipes,
  not a proposed multi-output protocol.
- [Processor adapter](/files/config/keybindings/processor.ts): current manifest
  capture, pure domain call and sole-candidate write.

# What became possible—and what did not

Possible now:

- Package action and binding YAML through the real Ansible artifact machinery;
  render both targets without rewriting source-builder playbooks.
- Change one action command and rebuild all referencing binding definitions;
  change only a user chord without repeating the command.
- Preserve intentional Niri/Umbriel chords, add target-specific keys/options,
  and render explicit native actions without inventing portable counterparts.
- Create independent native definitions and include material. Context-bound
  includes point at effective user placement, not the producer's path.
- Feed an authored native source to the same include processor.
- Use check/stdout without publishing, and reject malformed/unresolved updates
  while retaining an earlier assembled output.
- Import the semantic core later under CFR draft2 without filesystem, install,
  environment or scheduler initialization on import.

Not claimed:

- Generated contributor installers, coherent registration batches, actual
  copy/link/seed/refresh delivery or existing-root adoption.
- Production whole-consumer staging and validation across all recipe candidates.
  Reference recipes do not validate existence or bytes of selected user copies.
- A source snapshot shared across every per-binding/target recipe. The current
  adapter captures its own selected inputs separately for each invocation.
- A dependent-candidate DAG, a multi-output processor, crash-atomic multi-file
  delivery, pruning, compositor reload or arbitrary executable output support.

The full-root tests construct an isolated candidate include layout and run native
validators against it. They prove native syntax and fragment composition, **not**
an already-shipped installer transaction. Adding a root recipe that reads pending
fragment outputs through ordinary file inputs would validate old live files and is
not acceptable.

# Verification

All reported checks passed:

- `pnpm exec vitest run tests/config-keybindings` — **14 tests**, no skips on this
  host. Includes both native validators; each complete candidate root includes
  separate command and target-native binding fragments, and rejects an invalid
  action after a valid candidate layout.
- `python tests/integration/keybindings_packaging.test.py` — real
  `ETC_FILES.yaml`, existing artifact tasks, generated external leaves and the
  deployed bundled processor.
- `python tests/integration/config_external_processor.test.py` — argv quoting,
  stdout/check/apply, 0600 output and preservation after processor/validator errors.
- `python tests/filter_plugins/config_compile.test.py` — existing processors plus
  external declaration validation and quoting.
- `python tests/filter_plugins/config_context_compile.test.py` — existing context
  compilation and runtime ownership remain compatible.
- `python tests/integration/config_graph.test.py` and
  `python tests/integration/config_contexts.test.py` — legacy built-in processors,
  remote inputs and context binding remain functional.
- `pnpm build`, `pnpm check:type`, targeted Vite+ lint and format checks.

The deployed-runtime test copies only the bundle into an unrelated test consumer,
without TS sources or node_modules. It exercises both inclusion and YAML-backed
definition processing. Scratch is confined to `.test-agent/keybindings/` with a
README and individually cleaned fixture directories.

# Next coherent slice for parent review

Build a **TypeScript domain assembly/install adapter over existing CONFIG and
LINKS delivery**, with the Zim-style explicit owner/binding pattern—not a parallel
general installer framework. Then generate participation automatically from
action/binding declarations. Continue isolated consumers first.

The adapter should:

1. Capture explicit source membership and effective consumer settings once for a
   bounded operation; register action/binding resources as one graph-changing batch.
2. Reuse existing copy/link primitives. Normal reassembly reads edited user copies;
   seed and explicit refresh are distinct. Missing selected copies fail or undergo
   explicitly requested seed; no producer fallback.
3. Render per-binding candidates via the current external processor seam, build a
   complete temporary native layout, and rewrite candidate validation references
   to staged files. Bind live references to effective placement separately.
4. Reuse block-in-file for contribution-based root incorporation. Niri can include
   or inline complete `binds` fragments; Umbriel starts include-driven, not raw body
   concatenation. Preserve unrelated root text and baseline/personal ordering.
5. Validate before activating, preserve ordinary failure rollback and root-change
   checks, and invoke the current assembly commit exactly once at its intended
   boundary. Do not treat ordinary assembly as prepare-only then double deploy.
6. Generate generic Niri/Umbriel installer participation, with explicit target and
   consumer/context bindings. No PATH scan or custom producer install bodies.

Consequential decisions to review before that slice:

- **Root adoption:** recommend creating managed missing roots from a readable
  skeleton and initially accepting only explicitly adopted/managed include areas
  in existing roots. Existing arbitrary Umbriel `[include]` tables require an
  explicit structured/adoption policy; never append a second table.
- **Block identity/comment seam:** generic block-in-file currently derives
  identities from manifest positions and lacks a configured comment marker.
  Niri requires `//`, and contribution IDs must survive source switches/order
  changes. Prefer a small supported block setting/TS adapter extension over
  making each producer supply custom installer text.
- **Bounded staging/publication:** current per-output processors and transaction
  runner cannot assemble a root from other pending candidates. Choose the exact
  wrapper seam that prepares the temporary layout and performs one existing
  commit; do not silently advertise another transactional executor.

After this checkpoint is reviewed, the next adapter can preserve the agreed
direct/copy/link and Niri inline paths without making authored native files a
separate subsystem. Vicinae cutover and live deployment remain later gates.

# Cross-references

- [Mise2](/mise2.opt.pb) and [Zim2](/zim2.opt.pb): concrete existing block placement,
  explicit CONFIG owner and context/install infrastructure being reused.
- [Consumer toolkit](/doc/config/consumer-toolkit.md): source of copy/link/seed and
  current assembly behavior; next delivery code should compose these operations.
- [Current CONFIG proposal](/design/keybindings/current-config0.gpt6a.md): small
  external seam and reusable domain core; its aggregate output sketch is superseded
  by the agreed per-binding definitions and incorporation.
- [Earlier lifecycle proposal](/design/keybindings/config-lifecycle0.gpt61sol.md):
  lifecycle distinctions retained, prerequisite general CONFIG redesign not built.
- [CFR draft2](/design/compfuzor-runtime/effect-draft2.gpt6a.md): future native
  admission and capture/history contract, not an implemented dependency here.
