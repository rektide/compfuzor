---
type: ImplementationGuide
title: Named action and keybinding processors
description: The first TypeScript domain slice over existing filename-keyed CONFIG recipes, with separate native definitions and incorporation material.
resource: /doc/config/keybindings.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - resource: /files/config/keybindings/model.ts
    title: Pure action and binding composition
  - resource: /files/config/keybindings/processor.ts
    title: Current single-candidate CONFIG adapter
  - resource: /tests/integration/keybindings_packaging.test.py
    title: Packaging and deployed processor proof
---

# What is implemented

**Consumer delivery is now implemented in the next slice:** see
[consumer assembly and delivery](/doc/config/keybinding-consumers.md) for staged
copy/link, seed/refresh, adopted root areas, native closure validation and coherent
registration. The final boundary section below records the original first-slice
gate; current behavior and remaining limits live in that companion guide.

**Processor** renders one private candidate for a recipe. **Assembly** selects
inputs, runs processors, validates candidates, and commits outputs. This slice
adds a TypeScript processor, not another executor or an Effect rewrite.

It uses the same CONFIG world as [Zim2](/zim2.opt.pb): filename-keyed recipes,
explicit context bindings, and the sole transactional runner. [Mise2](/mise2.opt.pb)
also shows direct block-in-file installation; the target-root installation slice
will reuse this existing placement machinery, rather than give each producer its
own handwritten compositor installer.

The pure modules under [config/keybindings](/files/config/keybindings/) decode,
compose, resolve and render without filesystem, environment, installation or
scheduler side effects. The [processor adapter](/files/config/keybindings/processor.ts)
captures the current runner's selected YAML inputs and writes only
`CONFIG_CANDIDATE`. The deployed alias `keybinding-processor.mjs` uses the existing
omnibus runtime, including its bundled YAML dependency. For development invoke
`node files/config/keybindings/command.ts` through the internal CONFIG protocol.

# Authoring and packaging

Each declaration is one versioned source record. Ship directly under ETC's
**singular** domain directories; no action/binding aggregation envelope is needed:

```yaml
ETC_FILES:
  - name: action/launcher.yaml
    yaml:
      version: 1
      kind: action
      id: launcher
      exec: [vicinae, toggle]
  - name: keybinding/launch.yaml
    yaml:
      version: 1
      kind: keybinding
      id: launch
      action: launcher
      keys: [Mod+D]
      title: Run an Application
      umbriel:
        keys: [Mod+Space]
```

Several bindings can reference one action, including actions from other source
files. A user does not repeat the command to change the chord:

```yaml
version: 1
kind: keybinding
id: launch
patch: true
keys: [Alt+Space]
```

Inputs are ordered. Duplicate definitions fail unless the later record explicitly
says `patch: true`; a patch without an earlier definition also fails. Each source's
target refinement is applied **before** moving to the next source, so a later user
patch does not get hidden by an earlier producer's target-specific default.

Field-specific rules:

- `exec` replaces the complete argv. Strings are not implicitly shell programs.
- `script: {shell: /bin/bash, body: '...'}` is explicit trusted shell material;
  it renders a direct native spawn of the shell with `-c`, not a generated executable.
- `niri.native: {name: focus-workspace, args: [2], properties: {}}` and
  `umbriel.native: 'workspace-switch:2'` are target-native replacements.
  Native implementations only appear under a target specifier.
- `keys` replaces the complete current chord selection, including earlier additions.
  `add-keys` deliberately unions additional chords; it does not concatenate argv.
- `options` merges scalar properties by name. Use target specifiers for native
  spelling differences such as Niri's `allow-when-locked` versus Umbriel's options.
- `enabled: false` suppresses the named entity for that target. `keys: []` retains
  a binding identity without rendered chords. References to disabled or unavailable
  actions fail. A native action with no implementation on another target is fine
  if no enabled binding on that target references it.

Sources and identifiers survive composition for diagnostics. Duplicate YAML keys,
multiple documents, malformed argv, unknown fields and unresolved action references
fail. The initial chord grammar covers ordinary alphanumeric/XKB-name `+` chords;
submaps, release prefixes and other advanced forms can enter as authored native
files instead. Conflict detection normalizes modifier order/case only; it does not
guess configurable `Mod` equivalence or every XKB alias. Native validation remains
the authority for target semantics and option support.

# Native definitions and incorporation are different material

| Target | Definition | Incorporation |
|---|---|---|
| Niri | `niri/<id>.binding.kdl`, complete `binds {...}` | `niri/<id>.include.kdl`, one include statement |
| Umbriel | `umbriel/<id>.binding.toml`, one `[keybinds]` table | `umbriel/<id>.include.toml.part`, one `"path",` array entry |

The `.binding` suffix makes material kinds explicit and avoids filename collisions
for valid IDs such as `launch.include`. **Do not glob `niri/*.kdl` for definitions**:
incorporation pieces are not binding definitions. Membership is explicit.

[projectionRecipes](/files/config/keybindings/recipes.ts) expands the captured
binding inventory into multiple single-output recipe declarations, one definition
and one incorporation recipe per selected binding. The processor declaration uses
the new generic external seam:

```yaml
CONFIGS:
  niri/launch.binding.kdl:
    name: keybinding-niri-launch-definition
    processor:
      command: keybinding-processor.mjs
      args: [--target, niri, --binding, launch, --material, definition]
    inputs: [{file: action/launcher.yaml}, {file: keybinding/launch.yaml}]
  niri/launch.include.kdl:
    name: keybinding-niri-launch-include
    processor:
      command: keybinding-processor.mjs
      args: [--target, niri, --material, include]
    inputs: [{file: niri/launch.binding.kdl}]
```

Commands are absolute executable paths or paths relative to the deployed
`$DIR/bin`; fixed arguments are shell-quoted independently, not interpreted as a
command string. The command must already be deployed. Add the stable alias through
ordinary BINS alongside the existing runtime claim:

```yaml
BINS:
  - name: keybinding-processor.mjs
    dest: keybinding-processor.mjs
    link: compfuzor-runtime.mjs
    compose: false
    basedir: false
```

The incorporation recipe takes **one explicit native file input**, and renders its
selected input path without reading its live body. Existing context input binding
therefore controls where the include points. It is not tied to the producer's
canonical pathname. This same interface admits native user-authored KDL/TOML files
without any action YAML.

[selectMaterials](/files/config/keybindings/materials.ts) is the pure placement
seam: explicit `id`, `path`, target `format`, `order`, and either direct-source
placement or copy/link destination. Stable block IDs are contribution-based, not
absolute-path-based. The root renderer produces a **new skeleton only**: baseline
references first, ordered contribution references, personal references last.
Umbriel gets exactly one `[include]` table. It never concatenates `[keybinds]`
tables or pretends an array-entry fragment is standalone TOML.

# Original first-slice boundaries (superseded by the consumer guide)

This first slice is intentionally **not a live target installer**. In particular:

- No Vicinae or KDE cutover; no live root adoption or user-config mutation.
- No automatic producer installer generation or registration batch yet.
- Copy/link plans do not perform filesystem delivery. The next adapter must reuse
  existing CONFIG/LINKS primitives, preserve edited copies on normal reassembly,
  distinguish seed from explicit refresh, and fail on missing selected copies.
- Include rendering is metadata, not source-existence validation. Its source may
  be another output that has not been committed yet. A full-root validator must
  bind references to the **candidate layout**, not accidentally validate old live
  fragments. Native candidate-root tests prove the render shape, not a production
  staging/activation transaction.
- There is no candidate DAG in the current runner. Do not add a root recipe that
  assumes it can read other pending recipe candidates. Bounded orchestration must
  prepare an explicit native candidate layout before root validation/commit.
- Ordinary assembly already commits. It must not be called as though prepare-only
  and then redundantly redeployed. New outputs still use the runner's 0600 mode;
  no arbitrary executable output feature is claimed.
- Each definition processor captures its own selected YAML inputs. Several recipes
  do not share a frozen source revision merely because they share a spec.
- Explicit source membership does not imply stale-file pruning.

# Verification and cross-references

The outer [advertised-registry admission layer](/runtime/registry/README.md#advertised-keybinding-execution)
connects playbook-owned offers and consumer descriptions. It does not change this
pure action/binding grammar or native source interface. Receiver identity differs
from native target format; host assembly remains closed accepted-membership reassembly.

Run:

```sh
pnpm exec vitest run tests/config-keybindings
python tests/filter_plugins/config_compile.test.py
python tests/integration/config_external_processor.test.py
python tests/integration/keybindings_packaging.test.py
pnpm check:type
pnpm exec vp lint files/config/keybindings files/runtime/compfuzor-runtime.ts
```

The native tests invoke Niri and Umbriel validators when present (otherwise they
are skipped). Fixtures live under `.test-agent/keybindings/`; no live compositor
configuration is used.

- [Consumer toolkit](/doc/config/consumer-toolkit.md): existing context selection,
  delivery and assembly semantics retained for the next installer slice.
- [Current CONFIG proposal](/design/keybindings/current-config0.gpt6a.md): source of
  the small external seam and future importable-domain admission; per-binding
  definitions/incorporation supersede its earlier aggregate-fragment sketch.
- [CFR draft2](/design/compfuzor-runtime/effect-draft2.gpt6a.md): future native
  admission can import these domain modules without changing their semantics;
  this slice adds no proposed Effect APIs.
- [Packaging integration](/tests/integration/keybindings_packaging.test.py): actual
  `ETC_FILES.yaml`, existing artifact tasks, generated executable leaves and the
  deployed bundled processor, rather than a controller-only rendering shortcut.
