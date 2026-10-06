---
type: ImplementationGuide
title: Declared keybinding producers and consumer profiles
description: Automatic singular YAML packaging, generated scoped target installers and durable explicit membership using the shared TypeScript CONFIG consumer.
resource: /doc/config/keybinding-producers.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - resource: /library/filter_plugins/keybindings_compile.py
    title: Thin declaration packaging and installer synthesis
  - resource: /files/config/keybindings/membership.ts
    title: Durable membership and context-bound installation
  - resource: /tests/integration/keybindings_generated.test.py
    title: Actual stock rendered installation proof
---

# Producer authoring: no per-binding plumbing

The public names are **`KEYBINDING_ACTIONS`** and **`KEYBINDINGS`**. A producer
declares named records; it does not write ETC_FILES, CONFIGS, target text or BINS
for individual bindings:

```yaml
ACTION_AUDIENCES: {default: user}
KEYBINDING_ACTIONS:
  terminal-open:
    exec: [foot]
KEYBINDINGS:
  terminal-open:
    action: terminal-open
    keys: [Mod+Return]
    title: Open a Terminal
    umbriel:
      add-keys: [Alt+Return]
KEYBINDING_TARGETS:
  niri:
    consumer: {env: COMPFUZOR_NIRI_PROFILE, default: "${XDG_DATA_HOME}/compfuzor/etc/niri/etc/keybinding-niri.json"}
    context: user
    scope: user
  umbriel:
    consumer: {env: COMPFUZOR_UMBRIEL_PROFILE, default: "${XDG_DATA_HOME}/compfuzor/etc/umbriel/etc/keybinding-umbriel.json"}
    context: user
    scope: user
```

Normal playbook task entry remains `tasks/compfuzor.includes`. The thin generator
packages `action/<id>.yaml` and `keybinding/<id>.yaml` directly under ETC, using
the existing YAML artifact writer. It stamps `version`, `kind`, and the named ID;
an explicitly supplied conflicting ID/kind/version is an error. Runtime YAML IDs
are authoritative; filenames are provenance, not another naming scheme.

`KEYBINDING_PRODUCER` defaults to deployment NAME and identifies a durable
**membership group**, not an action prefix. It can be declared explicitly.
`KEYBINDING_ORDER` defaults to 100. Named action/binding IDs remain global in a
consumer graph; use readable application prefixes. Accidental duplicate
definitions still fail, while intentional `patch: true` retains the domain's
field-specific override behavior.

`KEYBINDING_TARGETS` accepts a list of targets or the explicit bindings above.
If omitted for an ordinary producer, Niri and Umbriel target entries are generated
using known user defaults—never PATH discovery. Set the list to the intended
targets. A `consumer` is an explicit deployment or profile JSON path. A deployment
resolves to `etc/keybinding-<target>.json`; HOME/XDG-rooted profile paths and existing
env/default selectors resolve at invocation. For example,
`consumer: "${XDG_CONFIG_HOME}/umbriel/keybinding-umbriel.json"` binds a user host
without baking the controller's home directory into a system producer. Selector
mappings select a profile file. No universal consumer registry is added.

The compatible generated commands are `install-keybindings-niri.sh` and
`install-keybindings-umbriel.sh`. They call the shared installed TypeScript runtime
with the packaged manifest, target, context and declared scope. Normal bin
composition creates one subsystem/user aggregate and calls each target exactly
once. An authored system `install.sh` remains a system builder/installer; an
authored `install-user.sh` retains its own body and gains the scoped children.
Generated installers have `run: false`: rendering is not deployment or reload.
With `ACTION_AUDIENCES`, those records contribute complete typed operations behind
one real `install-user.mjs` plus `install.mjs` (and an available system alias).
Public subsystem action families remain available without a per-context wrapper
matrix. Native selection/admission is fixed before authored effects; see
[general actions](/doc/actions/README.md) for audience/flag/bypass semantics.

## Runtime packages and separately provided commands

Both ordinary CONFIG and standalone keybinding generation reuse the same worker
package contribution: **`PKGS: [jq]`**. `gen_keybindings.tasks` merges it once into
the playbook package metadata, even when no ordinary `CONFIGS` are declared. This
declares the requirement; it does not opportunistically run package installation.

The existing runtime convention provides the other commands separately:

- **Node** must satisfy the [repository engine range](/package.json). The
  deployment executes the bundled `.mjs` through Node; it does not need receiver
  node_modules. [NodeSource provisioning](/nodesource.repo.pb) is the existing
  explicit `nodejs` package/repository entry, not a dependency silently activated
  by this generator. Do not set `NODEJS: true` merely for the runtime: that
  subsystem describes source package build/install work.
- **`block-in-file`** is a separately deployed command, not an invented apt
  package. [Its source playbook](/block-in-file.src.pb) builds/promotes a standalone
  artifact and exposes a global command. It needs the supported comment, named
  block/removal, before-placement, source-attribution and timestamp options.
  `CONFIG_BLOCK_IN_FILE` can bind its explicit command path, just as in the
  [Mise2 block installers](/mise2.opt.pb).
- The explicitly selected **Niri/Umbriel validator** must be available. Source
  provisioning remains owned by [niri.src.pb](/niri.src.pb) and
  [umbriel.src.pb](/umbriel.src.pb); the keybinding installer does not discover or
  install compositors. Missing prerequisites fail preparation rather than
  skipping target validation or mutating live output.

This follows current CONFIG's package-versus-external-command convention. The
standalone generator now contributes the same worker packages, while these
non-package prerequisites are explicit operator/deployment requirements.

# Consumer profiles: ordinary context/root conventions

A host declares target policy once:

```yaml
KEYBINDING_CONSUMERS:
  niri:
    contexts:
      user: {scope: user, root: config, subpath: niri}
    baseline: [/absolute/niri-baseline.kdl]
    personal: [personal.kdl]
    placement: copy
    registration: copy
    native_sources:
      - {id: own, path: own.kdl, order: 9000, placement: direct}
  umbriel:
    contexts:
      user: {scope: user, root: config, subpath: umbriel}
    baseline: [/usr/local/share/umbriel/config.toml]
    personal: [keybinds-local.toml, animation.toml]
    placement: link
    registration: link
```

`scope`, named `root` (`config`, `state`, `home`, etc.), `subpath`, and
env/default path selectors reuse current CONFIG conventions. User roots resolve
HOME/XDG at invocation, independently from producer source/material placement. A
generated user entry cannot silently select a system-scoped context: the runtime
checks the context against its declared scope.

Defaults are user `root: config`, `subpath: <target>`, `config.kdl` or
`config.toml`, `.keybindings/generated`, and `keybindings/` placement. Umbriel's
built-in profile includes `/usr/local/share/umbriel/config.toml`; Niri's built-in
profile has **no fabricated baseline**. Declare the desired baseline when making
a complete fresh Niri configuration. Existing roots still require the adopted
insertion area described in the [consumer guide](/doc/config/keybinding-consumers.md).
No default overwrites/adopts an arbitrary existing file.

This is a domain installation owner over CONFIG workers, like Zim's owner
pattern. If replacing an existing ordinary CONFIG installer for the same root,
declare `CONFIG_INSTALL_OWNER: keybindings` to suppress that duplicate install
participation. Unrelated CONFIG recipes retain their existing owner; the
keybinding generator does not silently take ownership of every other subsystem.

Other profile fields are `root_file`, `material_root`, `membership`,
`placement_directory`, `template_file`, and binding-specific `bindings` policies.
These paths accept the existing selector grammar, including relative-to-context
paths and `{env: VARIABLE, default: ...}`. Native sources use the same explicit
ID/path/format/order/placement/incorporation interface as generated material.
There are no native suffix-wide scans.

A host's own `KEYBINDING_ACTIONS`/`KEYBINDINGS` resources become its late user layer
when `KEYBINDING_CONSUMERS` is declared, unless it explicitly also declares producer
targets. For example, a chord override does not repeat the command:

```yaml
KEYBINDINGS:
  terminal-open:
    patch: true
    niri: {keys: [Alt+Return]}
```

These packaged consumer-owned patches are persisted in the generated profile,
not in each application's include list. Patch records are explicitly
`whenPresent`: they remain dormant while their producer is absent/disabled and
activate only when the named base exists. Unconditional core patches remain
strict. Additional receiver-owned `user_sources` can be declared by path with
`when_present` and `disabled_suffix`; they are ordered after producers and host
declarations. Native user files can likewise be declared once in the profile.

# Source registrations versus editable material

The two strategies are deliberately separate:

| Policy | Install/reinstall behavior |
|---|---|
| `registration: link` | Refresh each managed YAML registration link to the declared producer file. |
| `registration: copy` | Refresh managed YAML declaration copies from the producer on explicit reinstall. These are not the editable native copies. |
| `placement: copy` | Seed missing native receiver files, preserve existing edits on ordinary reinstall/reassembly. |
| `placement: link` | Seed a native receiver link to the newly rendered canonical definition; linked data tracks future definition updates. |
| `placement: direct` | Include the canonical definition directly. |

User overrides belong in the user layer or selected native copies, not edits to
managed YAML registrations. Explicit `--mode refresh` replaces declared native
placements; default producer installation is `seed`. Reassembly does not silently
restore a producer over an edited user copy.

# Durable closed membership and failure semantics

Each context stores `.keybindings/membership.json`. It lists named producer groups,
their order/enabled state and **exact** registered resource paths/identities. The
registration directory is `.keybindings/source/<producer>/<action|keybinding>/`;
producer packaging itself remains flat singular directories directly under ETC.

Group order is numeric, then producer ID; user layers follow. Membership is not
inferred by scanning directories. Reinstalling fewer declarations replaces that
group's declared resource list. Old physical files remain, but no longer enter
assembly. Neither stale registrations nor native artifacts are auto-pruned.

This includes removing the **last** resource: keep the producer's target bindings
and declare empty `KEYBINDING_ACTIONS: {}` / `KEYBINDINGS: {}`. Rendering replaces
its manifest with an empty resource list, and the generated installer still runs
producer installation to commit empty membership. It never falls back to an old
manifest or changes into a host reassembly operation. An implicit consumer-only
host (`KEYBINDING_CONSUMERS` without producer targets) remains a distinct role.

Registration preserves existing active/disabled slots. Group enabled state also
survives reinstall. A binding registration named `*.yaml.disabled` stays disabled
when its producer is updated. A disabled group is excluded while its files remain.

Membership updates are ordinary single-output recipes in the **same existing CONFIG
transaction** as definitions, placements, companions and root. They are not saved
as accepted state before output validation/commit. The shared registration batch
installs action/binding resources coherently, invokes assembly once, and restores
prior entries after normal failure. CONFIG restores staged metadata/output entries
on a later publication failure. This is not crash atomicity or concurrent-reader
isolation; the observed-state guards still apply.

The registration preflight also rejects any destination/disabled slot reaching
another batch donor, including through symlinks/parent aliases. It does not rely
on later copying a donor that an earlier entry may have replaced.

# Commands

Current audience-mode operations use general generated action families, not a
human-authored request JSON or bespoke domain command:

```sh
/producer/bin/install.mjs
/producer/bin/install-user.mjs
/host/bin/install.mjs
/host/bin/assemble.mjs --check
```

Legacy deployments without `ACTION_AUDIENCES` keep `install-user.sh` and the
compatible target installers. Low-level `keybindings.mjs` remains available for
explicit membership control and debugging, not the ordinary audience-mode endpoint.

The host runtime can explicitly control membership:

```sh
/host/bin/keybindings.mjs disable --profile /host/etc/keybinding-niri.json \
  --target niri --context user --scope user --group terminal
/host/bin/keybindings.mjs enable --profile /host/etc/keybinding-niri.json \
  --target niri --context user --scope user --group terminal
/host/bin/keybindings.mjs host --profile /host/etc/keybinding-niri.json \
  --target niri --context user --scope user --mode assemble --check
```

Development uses `node files/config/keybindings/command.ts` with the same commands
and an explicit `--runner` when outside a deployment. No unrequested compositor
reload is performed. Existing bypass wrappers remain in force.

# Home-local consumer and producer example

The real host playbooks now stage material under
`${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/{niri,umbriel}`. The Media Keys
producer uses the same material group with its declared NAME. This example chooses
an explicit stable producer NAME using the existing override:

```sh
ansible-playbook -i 'localhost,' -c local niri.etc.pb
ansible-playbook -i 'localhost,' -c local umbriel.etc.pb
ansible-playbook -i 'localhost,' -c local media-keys.etc.pb -e NAME=media-keys

material="${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc"
"$material/niri/bin/install.mjs"
"$material/umbriel/bin/install.mjs"
"$material/media-keys/bin/install.mjs"
"$material/niri/bin/assemble.mjs" --check
"$material/umbriel/bin/assemble.mjs" --check
```

Generation does not modify the `.config` receiver roots. Host install performs
explicit conservative adoption/seed/migration; producer install registers exact
membership and validates both native targets through CONFIG. Host assembly uses
existing placements; `--check` validates without publishing. Delivery link/copy/
assemble choices are separate from both audience and material location.

Niri/Umbriel host declarations currently contain only user contexts. Therefore
`install-system.mjs` and `assemble-system.mjs` are absent, not aliases that secretly
fall back to user configuration. To support a real system receiver, declare its
actual scoped context/root and (for external producers) `action_contexts`; mere
shared placement is insufficient. Isolated tests exercise both audiences from
the same home-local profile without claiming a new compositor system fallback.

For explicitly shared consumers, keep their material location and bind profiles:

```sh
ansible-playbook -i 'localhost,' -c local niri.etc.pb -e PREFIX_DIR=/etc/opt
export COMPFUZOR_NIRI_PROFILE=/etc/opt/niri/etc/keybinding-niri.json
export COMPFUZOR_UMBRIEL_PROFILE=/etc/opt/umbriel/etc/keybinding-umbriel.json
"$material/media-keys/bin/install.mjs"
```

Unset those environment overrides to use invocation-time home-local defaults.
Vicinae uses the same selectors but keeps its source build/deployment and existing
service audience policy. Its compatible `install-user.sh` still enables a user
service; do not confuse rendering its declarations with authorization to build,
install or start Vicinae.

## Deliberate migration only

1. Keep old `/etc/opt` material and current receivers intact while generating the
   new material. Inspect the host profile paths, context scopes, templates and
   producer NAME/group identity before installation.
2. Choose old shared or new local consumers explicitly through the existing
   profile selectors. Adopt the intended host with its new `install.mjs` only as
   the desktop user; existing user edits are not silently overwritten.
3. Reinstall each producer deliberately to refresh the declared registrations.
   Preserve stable `KEYBINDING_PRODUCER` if changing deployment NAME would otherwise
   create a different membership group. Disable an obsolete group explicitly if
   that is the intended migration; do not infer pruning from a filename change.
4. Run host `assemble.mjs --check`, review changes and apply assembly when desired.
   No automatic service reload/restart, compositor reload, tree move or cleanup is
   part of these steps. Remove old material only after manually reviewing references.

These are operator instructions, not a claim that this implementation migrated
any live consumer. Historical live adoption checkpoints retain their own evidence;
their older system-first material rationale is superseded by
[current action/placement direction](/design/action-audiences/implementation2.gpt61sol.md).

# Proof and cross-references

[Generated installation test](/tests/integration/keybindings_generated.test.py)
renders actual stock runner, processor and omnibus artifacts via the existing
Ansible tasks, then runs complete generated user aggregates. It installs two
producers into isolated XDG consumers with own patch/native inputs, checks copy
and link behavior, updates commands and smaller membership, rejects invalid
reinstall without accepting membership, and preserves disabled group/slots.
It also checks authored install bodies and exactly-once target participation.

- [Source/domain grammar](/doc/config/keybindings.md): action independence,
  explicit scripts/native implementations and target override/extension rules.
- [Consumer assembly](/doc/config/keybinding-consumers.md): adopted root areas,
  mirrored candidate closure validation and the existing publication boundary.
- [Vicinae declaration fixture](/examples/keybindings/vicinae.yaml): reviewed
  modern routes and target differences, now declared in the repo by
  [vicinae.src.pb](/vicinae.src.pb) against the [niri](/niri.etc.pb) and
  [umbriel](/umbriel.etc.pb) consumer-host deployments.
- [Placement and action proof](/tests/integration/action_placement.test.py): actual
  HOME/XDG defaults, root-template isolation, full user producer path, shared
  overrides and system receiver fixture; service commands are stubbed or not invoked.
- [Generator](/library/filter_plugins/keybindings_compile.py) and
  [membership runtime](/files/config/keybindings/membership.ts): controller glue
  packages data; TypeScript owns capture, identity, ordering and lifecycle.
