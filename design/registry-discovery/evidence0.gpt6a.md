---
type: ResearchEvidence
title: Existing collections, disabled entries, configuration libraries, and CLI evidence
description: Source-backed distinctions among Compfuzor catalogs and receivers, plus isolated Figments, Firmaments and Router/tab probes.
resource: /design/registry-discovery/evidence0.gpt6a.md
tags: [registry, catalog, receivers, disabled, xdg, figments, firmaments, cli]
status: draft
generated: { by: model:gpt6a, at: 2026-10-06 }
verified: { by: model:gpt6a, at: 2026-10-06 }
stale_after: 2026-11-06
sources:
  - resource: /design/registry-discovery/init0.gpt6a.md
    title: Operator-directed investigation brief
  - resource: /files/catalog/runtime.ts
    title: Workload inventory and closed flow selection
  - resource: /files/config/input-state.ts
    title: CONFIG donor and consumer input catalogs
  - resource: /files/zim/runtime.ts
    title: Host registration and contributor import
  - resource: https://github.com/rektide/figments/blob/main/src/operators/drop-in.ts
    title: Local Figments drop-in implementation
  - resource: https://github.com/rektide/firmaments/blob/main/packages/config/src/index.ts
    title: Standalone Firmaments configuration interface
  - resource: https://github.com/bombshell-dev/router
    title: Router source and current documentation
  - resource: https://registry.npmjs.org/@bomb.sh%2Frouter
    title: Published Router version and metadata
  - resource: https://registry.npmjs.org/@bomb.sh%2Ftab
    title: Published tab version and metadata
---

# Scope and source snapshots

This investigation follows the [broader brief](/design/registry-discovery/init0.gpt6a.md).
It records implementation facts before proposing a new shared module.

Local checkouts were inspected first. Router was absent from the archive, so
`dl https://github.com/bombshell-dev/router` acquired its source; the optional
GitHub wiki fetch failed. The source checkout succeeded. Canonical links below
are navigation references; the inspected local revisions were:

| Project | Checkout HEAD |
|---|---|
| `figments` | `23116357afda594fd1f9934c6b82961c30b3b9bb` |
| `firmaments` | `3961ba60e758b6cd73b95f4dd61c6ccdcaa979e9` |
| `gunshi-dirs-xdg` | `ce1d67ab9b9a8435006e6030795e3e2ea7c53733` |
| `xdgox` | `5a63e0d96cd274c6db0fb6092d9e42749d3d1bc3` |
| `bombshell-dev/router` | `0d41f2dd7fb50ca9b918a99a558efde2b8fb2e77` |
| `bombshell-dev/tab` | `9b1d4320e4ab56f1e72df65e278e8a767ba31bfc` |

All six checkouts were clean at inspection. Figments had no Git `origin` remote;
its canonical project URL is referenced by the local xdgox documentation.

# 1. Compfuzor already has several different collections

| Mechanism | Membership / contents | Authority and lifecycle |
|---|---|---|
| Deployment runtime catalog | Attributed contributors, resource references, commands, actions, flow IDs | Compiled inventory; flow membership is closed, with execution authority explicitly recorded |
| CONFIG input catalog | Declared donor/consumer relationships plus observed enabled/disabled slots and local extras | Context owns selection/delivery; CONFIG owns assembly/publication |
| Zim host registry link | A selected host locator | Contributor resolves it to a host installer; it is not the module roster |
| Zim channel roster | Ordered `zimrc`/`zimenv` fragments | Authored host roster plus explicitly imported producer fragments; CONFIG assembles each channel |
| Keybinding membership | Exact producer groups/resources, enabled flags and ordering | Durable accepted membership publishes with native CONFIG outputs |
| Mise cache catalog | Base cache areas plus areas for observed installed tools | Inventory generated from `mise ls`; cache-specific commands consume it |

## Workload catalog: inspectable, sometimes authoritative

[`RuntimeCatalog`](/files/catalog/runtime.ts#L9-L18) describes deployment work.
[`compile_runtime_catalog()`](/library/filter_plugins/runtime_catalog.py#L323-L335)
sets `execution.authority` to `legacy-shell`, `catalog`, or `action-audiences`.
Calling it universally nonauthoritative would be wrong: both supplied experiment
playbooks explicitly enable `RUNTIME_FLOW_EXECUTION`.

[`loadFlow()`](/files/catalog/runtime.ts#L209-L309) starts from declared IDs, checks
compiled descriptors, and applies a site layer. Site entries can change placement
without changing behavior, or remove a declared invocation with a narrow
`state: absent` tombstone. Unknown IDs fail. This is already layered selection,
but not open-ended receiver discovery.

The resource projection currently recognizes CONFIG, Zim, action-audience and
LINKS specs: [`_resource_records()`](/library/filter_plugins/runtime_catalog.py#L133-L149).
It is a useful catalog-to-registry attachment point, rather than evidence that
every runtime collection should be stuffed into `RuntimeCatalog` itself.

## CONFIG: disabled entries are already first-class observations

[`input-state.ts`](/files/config/input-state.ts#L36-L68) has an internal
`InputCatalog`, including donor state, logical filename, pattern, suffix and
consumer relationships. Discovery strips the disabled suffix before matching the
logical name and detects active/disabled conflicts
([enumeration](/files/config/input-state.ts#L150-L185)).

[`putInput()`](/files/config/inputs.ts#L162-L211) preserves the consumer's current
active or disabled slot. The donor's `initiallyDisabled` state determines placement
only when the consumer has neither slot. Enable/disable renames between slots
([mutation](/files/config/inputs.ts#L238-L271)). Existing behavior therefore already
distinguishes a producer's initial recommendation from a consumer's local choice.

Mutation/publication contracts differ even inside this area:

- CONFIG input mutation remains applied if the subsequent rebuild fails, returning
  code 4: [`rebuild()`](/files/config/inputs.ts#L82-L91).
- Canonical remote-input administration restores the old link on ordinary rebuild
  failure: [`config-remote`](/files/config-remote/runtime.ts#L124-L185).
- Keybinding candidate membership publishes with native outputs, with registration
  rollback around the complete operation:
  [`membership.ts`](/files/config/keybindings/membership.ts#L400-L420).

Shared entry observation must not silently unify these different write contracts.

## How Zim actually grows

1. A host's `ZIM_MODULES` roster renders into `<channel>.d/*.conf`; `enabled: false`
   renders `<name>.conf.disabled`. A nonhost producer renders separate
   `etc/zim/<channel>/{active,disabled}/` directories. See
   [`zim_fragment()`](/library/filter_plugins/zim_fragment.py#L419-L495).
2. A generated contributor installer discovers **one host** through `ZIM_HOST_DIR`,
   otherwise `ZIM_CONFIG_LINK` / the conventional host symlink, then the historical
   `/opt/zim-main` fallback. It calls that host's import command:
   [`gen_zim.tasks`](/tasks/compfuzor/gen_zim.tasks#L166-L189).
3. [`inventoryProducer()`](/files/zim/runtime.ts#L143-L172) enumerates the producer's
   two channels and active/disabled directories. It accepts regular files and
   symlinks and rejects duplicate active/disabled names.
4. [`importProducer()`](/files/zim/runtime.ts#L174-L211) passes each fragment through
   CONFIG `putInput(initiallyDisabled: ...)`, then assembles/builds touched channels.
5. A complete host install publishes config, installs loaders/builds caches, and
   installs its registry link using LINKS:
   [`installZim()`](/files/zim/runtime.ts#L86-L141),
   [`runRegistry()`](/files/zim/runtime.ts#L43-L84).

The module collection grows through declared host contributions and explicit
producer imports, not through adding entries to the deployment runtime catalog.
The host link is a singleton rendezvous; it is not a multi-host registry yet.

There is also a concrete naming gap: [`zim2.opt.pb`](/zim2.opt.pb) publishes a
`.../zsh/zim2/zimfw.conf` locator, while the generic contributor default probes
`.../zsh/zimfw.conf`. A contributor reaches the nondefault host via the existing
explicit selector/override, not simply because `zim2` installed itself.

## Mise: a useful counterexample to forced receiver abstraction

[`mise2.opt.pb`](/mise2.opt.pb) has Bash block destinations and an isolated Mise
configuration root, but it does not declare a CONFIG graph. Zsh activation is a
Zim module. The maintained guide already calls this out:
[`doc/config/README.md`](/doc/config/README.md#L127-L131).

Its cache catalog is a third collection shape:
[`detectTools()` and `main()`](/files/config-mise-cache.ts#L168-L255) query installed
tools, combine base and mapped areas, deduplicate by name, and stage a JSON catalog.
Failed discovery preserves the old catalog. An area is an inspectable cache/tool
resource, not necessarily an endpoint that receives contributed configuration.

# 2. Layering and XDG project evidence

## Figments has the implemented drop-in precedent

[`rektide/figments` drop-in documentation](https://github.com/rektide/figments/blob/main/doc/drop-ins.md)
describes sorted directories, per-file provenance, profile gating and `registryKey`.
The local code implements these features in
[`drop-in.ts`](https://github.com/rektide/figments/blob/main/src/operators/drop-in.ts).

The XDG helper returns user-first config roots and absolute `XDG_CONFIG_DIRS`
entries. Merge layering needs the reverse order:
[`core/xdg.ts`](https://github.com/rektide/figments/blob/main/src/core/xdg.ts).
Its current roots are config roots, not a general config/data/state discovery
policy. It uses `??` for `XDG_CONFIG_DIRS`, so an explicitly empty value is not
treated the same as an unset variable in that implementation.

Important limits verified by source and the isolated probe:

- `sortedFiles()` accepts regular directory entries only; ordinary symlinks and
  `/dev/null` symlinks are skipped.
- `extensions: [".json"]` ignores `.json.disabled`; without a suitable classifier,
  filtering suffixes first loses disabled identity.
- `registryKey` builds a dotted key path. `desk.alt.json` becomes `desk.alt` as
  nested keys, not the literal ID `desk.alt` accepted by Compfuzor's ID grammar.
- Missing-directory detection uses a broad `access()` catch. Compfuzor's discovery
  must distinguish missing roots from failures such as permissions.

Thus its **layering** and operator/provider separation are useful; its raw drop-in
scanner is not a correct receiver-registry implementation out of the box.

## gunshi-dirs-xdg supplies directory precedent, not wildcard discovery

[`rektide/gunshi-dirs-xdg` source exports](https://github.com/rektide/gunshi-dirs-xdg/blob/main/src/index.ts)
are ordinary TypeScript directory helpers. The inspected code does not import
Gunshi. It provides config/data/state/cache/runtime/log roots, app-name overrides,
systemd-path adapters, and ordered async iteration of existing roots.

[`createComposite()`](https://github.com/rektide/gunshi-dirs-xdg/blob/main/src/composite.ts)
preserves the supplied scope order and tests existence. It does not perform glob
expansion or merge entries. [`user.ts`](https://github.com/rektide/gunshi-dirs-xdg/blob/main/src/user.ts)
captures xdg-basedir defaults at import time and requires a complete directory set,
including runtime. That is not the invocation-bound, minimally required-root
contract Compfuzor needs. Borrow the domain vocabulary, not ambient initialization.

## xdgox is design evidence in this checkout

[`rektide/xdgox` README](https://github.com/rektide/xdgox/blob/main/README.md)
proposes typed facets, one-file/one-entry subregistries, XDG roots, and profile-aware
filenames. The checked-out `xdgox.ts` is **empty**. This source does not establish
the README's provider as an implemented dependency. Figments' drop-in operator is
the concrete similar implementation found during this investigation; direct
historical migration between the projects was not established.

## Firmaments exposes a small standalone configuration path

[`rektide/firmaments` config entry](https://github.com/rektide/firmaments/blob/main/packages/config/src/index.ts)
exports acquisition, pure composition, provenance and decoding. It does not import
the board entry. [`compose()`](https://github.com/rektide/firmaments/blob/main/packages/config/src/composition/compose.ts)
overlays low-to-high, recursively merges records and replaces arrays/scalars.
[`capture()`](https://github.com/rektide/firmaments/blob/main/packages/config/src/acquisition/source.ts)
retains source identity/revision and distinguishes failed acquisition from absence.

The [config guide](https://github.com/rektide/firmaments/blob/main/packages/config/README.md)
separates the optional `/board` entry, and the
[Node guide](https://github.com/rektide/firmaments/blob/main/packages/node/README.md)
currently supplies explicit JSON-file and environment sources, not XDG/glob/drop-in
discovery. Keyed board families instantiate requested items; enumerating an
open-ended collection's membership is a further contract, not supplied for free
by a keyed dependency graph.

The local packages use Effect **4.0.1**, are private, and the config manifest has a
workspace dependency on board even though its main entry does not load it.
Compfuzor currently uses **4.0.0-rc.118**. A production dependency decision must
resolve that packaging/version difference; the probes deliberately used each
project's own dependency closure.

# 3. Isolated execution evidence

Scratch source and README: `.test-agent/registry-discovery/`.

| Probe | Result |
|---|---|
| Figments + standalone Firmaments, lower full receiver plus higher `enabled:false` | Both retained the profile and composed disabled state |
| Firmaments field provenance | `enabled` attributed to operator contribution |
| Explicit recapture after removing operator contribution | Default enabled value reappeared; old snapshot remained disabled |
| Figments `.json` drop-ins with higher `.json.disabled` | Lower enabled entry survived: suffix support requires our classifier |
| Figments with higher `/dev/null` mask | Lower entry survived: mask support requires our classifier |
| Figments ordinary symlink advertisement | Omitted |
| Figments dotted filename identity | Interpreted as nested key segments |
| Standalone Firmaments source on Node 26.6.0 | Passed without constructing a board |

The combined Figments source probe first failed under Node 26 strip-only because
[`Tuple` uses a TypeScript parameter property](https://github.com/rektide/figments/blob/main/src/providers/tuple.ts).
The installed Node 26 also rejects the removed `--experimental-transform-types`
flag. The existing Node 22.20.0 with that flag ran the source probe successfully.
This is a source-mode integration issue, not a failure of its merge behavior.

# 4. Router and tab are viable, with a version-specific interface

The requested completion library is treated as **`@bomb.sh/tab`**, singular:
[`bombshell-dev/tab`](https://github.com/bombshell-dev/tab). The published versions
queried and installed into scratch were Router **0.7.1** and tab **0.0.22**.
Npm metadata reported Router's publication at `2026-09-30T23:59:37.973Z`.

[`Router`](https://github.com/bombshell-dev/router#readme) returns typed intents
(`help`, `version`, `execute`) and leaves effects to the application. Standard
Schema works with Compfuzor's existing
[`Schema.toStandardSchemaV1`](https://github.com/Effect-TS/effect) adapter; the
probe needed no additional schema library.

The Node 26 scratch probe verified:

- nested `/registry/list` routing;
- CLI scope overriding a lower values source;
- repeated `--target desktop --target deck` yielding an array;
- invalid scope and unknown execution flags rejected;
- help intent without invoking a handler;
- checkpoint/resume followed by normal execution intent;
- tab completion for a disabled candidate under `registry enable`.

**Main differs from npm:** the checked-out Router README exports `dynamic()` and
resumes checkpoints with a value-source array. Published 0.7.1 does not publicly
export `dynamic`, and its checkpoint takes a `Result<ValueSource[]>`. The published
interface worked in the probe; implementation must select a version deliberately
rather than coding to main's examples while installing npm latest.

Tab provides nested space-separated command paths and callbacks for option/
argument suggestions. Those callbacks are synchronous in the inspected source:
[`src/t.ts`](https://github.com/bombshell-dev/tab/blob/main/src/t.ts).
Await registry observation first, then install callbacks over that snapshot. There
is no published Router-specific tab adapter in the inspected exports; a small
Compfuzor CLI bridge should derive completion from the same command descriptions.

# Cross-references

- [Native contribution/discovery direction](/design/compfuzor-runtime/effect-draft2.gpt6a.md#3-default-discovery-and-loader-activities)
  — later native catalogs include live bindings and per-collector snapshots;
  inert registration lookup should complement that direction.
- [Consumer toolkit](/doc/config/consumer-toolkit.md) — current authority for
  CONFIG delivery, disabled entries, distinct mutation failure contracts and Zim
  activation beyond config assembly.
- [Earlier receiver plan](/design/runtime-sourcing/receiver-plan0.gpt6a.md) — code
  seams still useful, but the registry's ownership and disabled-state model need
  the broader revision derived from these findings.
