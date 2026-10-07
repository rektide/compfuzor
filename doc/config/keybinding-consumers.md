---
type: ImplementationGuide
title: Consumer keybinding assembly and delivery
description: Capture named declarations and native inputs, stage chosen placement, validate native closures and commit through the existing CONFIG runner.
resource: /doc/config/keybinding-consumers.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - resource: /files/config/keybindings/consumer.ts
    title: Bounded TypeScript consumer adapter
  - resource: /files/config/keybindings/closure.ts
    title: Native closure validation hook
  - resource: /files/config-run.sh
    title: Existing sole commit and rollback boundary
  - resource: /tests/config-keybindings/consumer.test.ts
    title: Isolated delivery and registration behavior tests
---

# What owns the operation

The [TypeScript consumer adapter](/files/config/keybindings/consumer.ts) captures
inputs and prepares bytes. **The existing CONFIG runner remains the only publisher
of definitions, placed bodies, companions and roots.** No processor installs
anything, and assembly is not called as preparation followed by another deploy.

The adapter captures YAML once per consumer operation and imports the same
[pure named-action/binding core](/doc/config/keybindings.md). It prepares native
body inputs and expands the selected inventory into ordinary single-output CONFIG
recipes using an existing deployed concat leaf. Root preparation reuses a shared
[block-in-file adapter](/files/config/blocks.ts). The original standalone domain
processor remains available; this bounded consumer path avoids pretending those
separate recipes form a dependent-candidate DAG.

## How this reuses CONFIG

[`gen_config.tasks`](/tasks/compfuzor/gen_config.tasks) synthesizes artifacts for
statically declared `CONFIGS`. Keybinding membership is selected at **invocation
time**, so a consumer does not need an authored `CONFIGS` recipe per binding:

- [The thin keybinding generator](/library/filter_plugins/keybindings_compile.py)
  reuses CONFIG's stock runner and processor artifacts. When ordinary `CONFIGS`
  already supply those workers, keybindings uses the same deployment runtime.
- [Consumer assembly](/files/config/keybindings/consumer.ts) turns the selected
  bindings, native placements, include companions and root into ordinary
  single-output `concat` recipes, then calls the
  [shared CONFIG assembly entry](/files/config/assembly.ts) once. Native closure
  validation is a CONFIG transaction hook, not a second publisher.
- [Membership updates](/files/config/keybindings/membership.ts) enter that same
  transaction as an additional output. Source registration has its own bounded
  rollback around assembly; it does not accept membership before CONFIG commits.

Thus keybindings owns **which contributions participate and their native form**;
CONFIG owns **candidate processing, validation hooks, publication and rollback**.

The current repo supplies [producer participation and durable explicit membership](/doc/config/keybinding-producers.md)
and [general audience action families](/doc/actions/README.md). New home-local
placement/action defaults were validated only in disposable HOME/XDG fixtures;
this implementation did not move, activate or clean up existing live deployments.

# Ordinary operator entry: home-local material, separate receiver

[`niri.etc.pb`](/niri.etc.pb) and [`umbriel.etc.pb`](/umbriel.etc.pb) generate material
at `${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/<host>`, using existing
PREFIX_DIR/DIR/ETC primitives. Their receiver remains
`${XDG_CONFIG_HOME:-$HOME/.config}/<host>`. The staged Umbriel root template is
material, not the live root; host install explicitly seeds/adopts the latter.

```sh
material="${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc"
"$material/niri/bin/install.mjs"              # same user plan as install-user.mjs
"$material/umbriel/bin/install.mjs"
"$material/niri/bin/assemble.mjs" --check     # no publication
"$material/umbriel/bin/assemble.mjs"          # existing-placement assembly + commit
```

No system aliases are emitted for these user-only declarations. Explicit real
system contexts can be declared and bound with `action_contexts`; advertised receiver
availability is asserted against its description/profile before authored effects,
never fabricated from a shared material directory. `-e PREFIX_DIR=/etc/opt`
explicitly retains shared material; advertisement and receiver roots are independent.
See the [complete example/migration guide](/doc/config/keybinding-producers.md#home-local-consumer-and-producer-example).

Material placement, audience and native delivery strategy are separate: user/sys
selects a declared receiver plan, while direct/copy/link and seed/assemble/refresh
govern receiver representation. Context/selector/strategy choices are frozen before
body effects. Authored adoption can still create a root or input before native
validation; transaction/publication ownership below is unchanged.

## Owned advertisement, not accepted membership

The generator packages `keybindings/consumers/<audience>/<id>.json` beside each
owned `keybinding-<id>.json` profile. A description has `version:1`, `id`, `adapter`,
`audience`, `enabled`, `profile`, `contexts` and `defaultContext`. Receiver IDs are
independent from native adapters: `deck-main` may use `niri`. Native execution currently
supports Niri/Umbriel only. Profile selectors reuse the existing portable grammar;
inspection validates their shape without opening a native profile or requiring env
values. Selected invocation binds them relative to the descriptor's physical directory.

```sh
/host/bin/register-keybindings-consumer-deck-main-user.sh
/host/bin/status-keybindings-consumer-deck-main-user.sh
/producer/bin/install.mjs --target deck-main
```

Passive registration exposes the exact owner-held description through a symlink,
without adoption/native validation. Host install publishes after successful native
work; assembly/check neither advertises nor collects newly offered providers.
They reassemble the consumer's **closed accepted membership**, user patches and
native sources. Provider installation remains the ingress that updates membership.

Effective masks veto native work, including `--force-enable`. Force skips only saved
registration disables for the invocation, never consumer-owned group/action/binding
disables or native validation. Lower passive owner publication may coexist with a
higher mask/override; availability and execution eligibility are separate facts.
Combined producer/host actions admit packaged prospective descriptions before bodies,
then bootstrap owned hosts before delivering the producer's frozen receiver batch.

Custom roots use one `--registry-policy PATH` or generated
`KEYBINDING_REGISTRY_POLICY` document for both provider and consumer collections.
Selected audience/sides are mandatory under an override; there is no default fallback.
See [rendezvous policy and publication contracts](/runtime/registry/README.md) for
schemas, audience separation and exact planned-publication guards. Relocating an
owner does not authorize automatic retargeting of an existing same-ID reference.

# Explicit request

Development entry:

```sh
node files/config/keybindings/command.ts assemble \
  --request /absolute/consumer.request.json --runner /deployment/bin/config/run.sh
```

The installed `keybindings.mjs` alias uses the existing omnibus runtime and its
deployment's runner. Native validators and `block-in-file` must be available;
there is no target discovery/installation scan. Every consumer path is explicit
and absolute.

Deploy the alias through ordinary BINS alongside the existing runtime claim:

```yaml
BINS:
  - name: keybindings.mjs
    dest: keybindings.mjs
    link: compfuzor-runtime.mjs
    compose: false
    basedir: false
```

This is one consumer runtime alias, not a handwritten installer per producer.
The deployment must already supply the normal CONFIG runner and shared concat
leaf. The request is data:

```json
{
  "version": 1,
  "target": "niri",
  "root": { "path": "/isolated/user/config.kdl" },
  "materialRoot": "/isolated/materials",
  "mode": "seed",
  "yamlSources": [
    { "path": "/producer/etc/action/launcher.yaml" },
    { "path": "/producer/etc/keybinding/launch.yaml" },
    { "path": "/isolated/user/keybinding/launch-override.yaml" }
  ],
  "bindings": {
    "launch": {
      "order": 20,
      "placement": { "strategy": "copy", "path": "/isolated/user/launch.kdl" }
    }
  },
  "nativeSources": [
    {
      "id": "own",
      "path": "/isolated/user/own.kdl",
      "format": "niri",
      "order": 30,
      "placement": { "strategy": "direct" },
      "incorporation": "include"
    }
  ],
  "baseline": ["/isolated/baseline.kdl"],
  "personal": ["/isolated/personal.kdl"]
}
```

YAML `id` is authoritative for named actions/bindings. Filenames and manifest
identities supply provenance only. A native input's explicit metadata `id` owns
its contribution; its filename does not become a competing identity.

Generated bindings default to direct placement under `materialRoot`; settings
can select copy/link and order. Settings do not add membership and can remain
when their source is disabled. Native input uses exactly the same placement and
incorporation path as generated material. `enabled: false` suppresses a native
source explicitly. `disabledSuffix` on selected YAML/native source registrations
preserves a declared active/disabled-slot convention; both slots existing is an
error. This does not infer disabled state from arbitrary filenames or silently
fall back from a missing selected copy to its producer.

# Placement and representation

| Selection | Behavior |
|---|---|
| Direct source | Include the source path; never copy or modify it. |
| Copy | Include the user placement; normal reassembly reads its edited bytes. |
| Link | Include the user placement; new/refresh delivery stages a symlink to the explicit source. |
| Niri inline | Insert the selected body's complete native text instead of an include statement. Relative includes are rebound to the selected body's directory. |
| Umbriel inline | Rejected: body insertion requires explicit table adaptation, not repeated `[keybinds]` concatenation. |

`mode: assemble` requires usable selected copy/link entries and preserves existing
entries. `seed` creates missing entries but preserves existing files, links and
edits. `refresh` explicitly replaces declared placements. Existing edited copies
can assemble even when an unneeded native donor has disappeared; refresh cannot.
An existing dangling selected entry fails unless explicit refresh can supply it.

Definitions and companion material remain separate. Include companions retain
the first-slice `.include.kdl` / `.include.toml.part` spelling; Niri inline
companions use `.inline.kdl`. Membership is explicit, never suffix-wide scanning.
Old, no-longer-selected files are not pruned.

The adapter rejects duplicate IDs, normalized/physical placement aliases,
root/source collisions, output/donor collisions and donor symlink chains that
would cycle through a placement before publishing. It uses the existing LINKS
physical-entry/path helpers rather than assuming textual paths are distinct.

# Missing roots and adopted areas

Missing roots use a readable template: baseline first, the managed contribution
area, then personal references. `root.templateFile` can supply another explicit
template. For existing roots, baseline/personal text is **not rewritten** from
request fields: those fields are bootstrap template policy, and existing text
remains its author's responsibility.

The default Niri insertion area is top-level:

```kdl
include "/baseline/config.kdl"
// compfuzor-keybindings-begin
// compfuzor-keybindings-end
include "/user/personal.kdl"
```

Umbriel's area must be inside the single required `include.files` array:

```toml
[include]
files = [
  "/baseline/config.toml",
  # compfuzor-keybindings-begin
  # compfuzor-keybindings-end
  "/user/personal.toml",
]
```

Explicit `root.area: {begin, end}` may use different comment lines. There must
be exactly one ordered pair, in the required native include scope. The adapter
probes that scope before insertion. An arbitrary existing Umbriel `[include]`
table without an adopted area fails; no second table or unrelated TOML rewrite
is added. The maintained Umbriel root can be deliberately adapted later.

Stable contribution block names are `keybinding/<target>/<id>`, independent of
source path or order. Niri uses `//`; Umbriel uses `#`. Only owned blocks within
the area are rebuilt, preserving other text. Orphaned/nested/duplicate markers,
owned markers outside the area, and reserved markers embedded in new material
are rejected. Source attribution and timestamps are disabled for these prepared
blocks, so private paths and incidental time do not become drift.

The shared adapter invokes the available `block-in-file` CLI only on private
preparation files. `CONFIG_BLOCK_IN_FILE` can select that existing command. The
published npm package inspected here does not expose the newer archive's library
entry points, so this implementation does not rely on unpublished toolkit APIs.

Ordinary CONFIG `block-in-file` recipes also gained generic stable-ID/comment
settings, without changing legacy defaults:

```yaml
CONFIGS:
  config.kdl:
    processor: block-in-file
    block: {comment: "//", before: "^// insertion anchor$"}
    inputs:
      - file: explicit-contribution.include.kdl
        block: {id: own}
```

`block.id` requires an explicit file input and must be unique within the recipe;
it cannot assign one ID to every member of a glob. Configure the comment marker
consistently on the recipe. Names remain `<recipe namespace>/<contribution id>`;
without `id`, the prior manifest identity is retained.

# Candidate closure—not old live includes

The generic runner retains every candidate, including unchanged outputs, and
runs optional spec-level `transaction_validate` **after** production and existing
per-recipe validation, **before** check/stdout/publication. The hook receives:

- `CONFIG_CANDIDATES_FILE`: `{version: 1, candidates: [{name, output, candidate, link}]}`.
- `CONFIG_TRANSACTION`, `CONFIG_SPEC`, and `CONFIG_MODE` (`apply`, `check`, `stdout`).

Generic Ansible declarations can set `CONFIG_TRANSACTION_VALIDATE`. Normal
per-recipe validation remains immediate. No hook means the legacy protocol and
commit ordering remain intact.

The domain hook recursively reads the staged root's include graph, substituting
map candidates for selected output paths and captured inputs for other references.
It builds a mirrored private layout and rewrites include paths **only in validation
copies**. Relative, absolute, tilde and optional includes are handled; explicit
`environment` values are required for Umbriel environment expressions (HOME is
the default projection). Cycles, missing required files, uncaptured references and
invalid UTF-8 fail rather than reading a secret live fallback.

The actual effective root is validated first. Generated canonical definitions
shadowed by edited copies are also admitted in a separate validation-only envelope
under the same consumer context, with the effective root last. This prevents
publishing invalid default native material merely because a user copy currently
shadows it; it does **not** change the effective root or validate fragments as
standalone configurations without their context.

Live root candidates and companions keep effective **live placement paths**, never
private validation paths. Guards compare captured bytes, file/link kind, literal
link target and resolved physical parent before and after native validation.
Observed root/source/topology changes abort instead of overwriting stale snapshots.
This is not locking or elimination of the check-to-commit race.

Optional per-recipe `link: /absolute/source` stages a sibling symlink at the
existing commit boundary. Candidate bytes remain available for validation;
the existing backup/move/rollback loop publishes the link. Ordinary files retain
existing regular-file modes or default to 0600. Runtime-expanded recipes can
explicitly select an already-deployed `leaf`; the per-name leaf remains the default.
There is no new multi-output processor, candidate DAG or executable-output mode.

# Coherent registration batch

[withInputBatch](/files/config/registration.ts) validates destinations and active/
disabled pairs, snapshots prior entries, uses existing copy/link primitives, and
calls the caller's assembly operation **once**, after all registrations are present.
Failed assembly or a thrown pre-commit error restores previous selected entries,
including disabled state and literal symlink targets. This is ordinary failure
rollback, not crash atomicity or isolation from concurrent assemblers.

The installed runtime also provides:

```sh
node files/config/keybindings/command.ts register \
  --request /absolute/consumer.request.json \
  --batch /absolute/registration.batch.json --runner /deployment/bin/config/run.sh
```

The batch is an array of `{source, destination, strategy, disabledSuffix?}` records.
The request selects the corresponding active resource paths and disabled-slot
convention. Registration changes membership links, not source IDs. `--check`
is assembly-only; registration is an explicit mutation operation.

This low-level primitive is now used by the [producer adapter](/doc/config/keybinding-producers.md),
which packages declarations, binds consumers/targets and stages durable membership
with CONFIG output publication. The producer API avoids handwritten per-binding
CONFIGS/BINS lists and repeated half-graph rebuilds.

# Verification and remaining limits

```sh
pnpm exec vitest run tests/config-keybindings
python tests/integration/config_closure.test.py
python tests/integration/config_transaction_faults.test.py
pnpm check:type
```

Tests exercise real native validation, direct/native sources, copy/link staging,
seed/check/refresh, edited copies, Niri inline, adoption, source/path switches,
registration rollback and disabled state, root revision guards, and installed
bundled execution without source or node_modules.

No live user configuration was changed. No auto-pruning, automatic reload, generic
runtime rewrite, Effect admission, crash-atomicity or concurrent-writer coordination
is claimed. External edits to unowned included files are the author's state;
failed assembly preserves managed outputs, not a magical earlier version of every
outside input.

## Cross-references

- [Named declarations](/doc/config/keybindings.md): source grammar, field-specific
  composition and material distinctions retained from the first slice.
- [Consumer toolkit](/doc/config/consumer-toolkit.md): shared CONFIG context,
  copy/link and existing publication semantics, not a competing installer framework.
- [Commit-seam decision](/design/keybindings/commit-seam0.gpt61sol.md): why a
  processor-only validator cannot inspect later candidates and why publication
  remains at the current runner's boundary.
- [Mise2](/mise2.opt.pb) and [Zim2](/zim2.opt.pb): concrete block-placement and
  explicit domain installation-owner patterns to reuse in producer generation.
