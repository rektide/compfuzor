# Configuration

Compfuzor compiles configuration declarations on the Ansible controller, then
installs a small built runtime that can assemble, publish, inspect, and update
configuration for a selected consumer context.

## Start here

- [General action audiences](/doc/actions/README.md) — opt-in `.mjs` action
  families and scoped composition; automatic CONFIG/keybinding context attachment
  is still pending, so existing context-aware deployments are not broadly opted in.
- [Consumer configuration toolkit](/doc/config/consumer-toolkit.md) — current
  commands, contexts, copy/link choices, portable JSON input placement,
  Zim workflow, and status semantics.
- [Simplification plan](/doc/config/simplification.md) — candid account of the
  remaining accidental complexity and the deletion-oriented route out.
- [Named actions and keybindings](/doc/config/keybindings.md) — first TypeScript
  processor slice, per-binding native/include material, and boundaries before
  compositor installation; no live cutover yet.
- [Keybinding consumer assembly](/doc/config/keybinding-consumers.md) — staged
  direct/copy/link and Niri inline, adopted root areas, native candidate closures
  and coherent registration through the existing CONFIG commit boundary.
- [Declared keybinding producers](/doc/config/keybinding-producers.md) — author
  actions/bindings directly, generate scoped installers and maintain durable closed
  membership without per-binding ETC_FILES/CONFIGS/BINS lists.
- [Attributed runtime flows](/design/config-anneal/execution-model0.gpt6.md) —
  current annealing checkpoint for contributors, composition, catalog order,
  and cross-plane execution policy.
- [Deployment log](/doc/config/log.md) — exact live render, activation, status,
  Vite+ packaging, and retained migration residue.

## Mental model

```text
playbook declarations
    |
    |  Python filter plugins (Ansible controller only)
    v
config.spec.json / zim.spec.json / links.json
runtime catalog + 01-99 indexed flow inventory
    |
    |  built JavaScript runtime (Vite+)
    v
consumer inputs -> validated assembly -> consumer output
       |                                  |
       +-- copy or link representations --+
```

There are three implementation environments:

| Environment | What lives there | Deployed? |
|---|---|---:|
| Ansible controller | Python declaration compilers such as `config_compile.py` | No |
| Source/build checkout | TypeScript source and `pnpm build` / Vite+ | No |
| Managed deployment | One built multicall `.mjs`, shell transaction/processors, specs, and stable command symlinks | Yes |

`config_compile.py` is not a bundler and does not run on the managed machine.
It normalizes YAML/Jinja declarations into data. Vite+ bundles the TypeScript
runtime separately.

## Public commands

Compfuzor creates six fixed action names, not one file per context, recipe, or
strategy:

```text
config-install.sh
config-assemble.sh
config-sync-inputs.sh
config-publish.sh
config-inputs.sh
config-status.sh
```

All six are symlinks through the CONFIG alias to the shared built multicall
dispatcher. CONFIG still chooses the action from `$0`, resolves a context, and
calls a focused internal operation.
The context defaults to `user`; a playbook may change `CONTEXT_DEFAULT` or a
domain-specific default. Copy/link/assembly remain runtime options.

## The `config-*` compositor lane

The `config-` prefix is also a generic compositor action, alongside `build`,
`install`, and `apply`: any authored bin named `config-<thing>.sh` aggregates
into a `config.sh` scope compositor for its deployment (see
[`bin_composers.py`](/library/filter_plugins/bin_composers.py), where the
action set is data). The lane is the extension point for deployment
configuration generators — scripts that (re)materialize configuration
artifacts for their deployment, such as per-host client snippets.

The two vocabularies share a namespace and coexist by construction:

- the six fixed CONFIG subsystem commands above arrive with `compose: false`
  (or, for `config-install.sh`, an explicit `action: install` that classifies
  it into the install lane ahead of filename grammar), so they never join the
  `config.sh` compositor;
- authored `config-<thing>.sh` generators join the lane unless they opt out
  with `compose: false`.

The resulting `config.sh` is a shell aggregate for authored domain generators,
**not** an alias for the fixed CONFIG runtime. For example, apt-cacher's
`config.sh` calls its `config-30proxy.sh` generator, while `config-assemble.sh`
and `config-inputs.sh` reach CONFIG through the shared multicall runtime. The
shared prefix does not imply a shared implementation or argument contract.

Like the other compositor lanes, `config.sh` executes through the legacy
shell compositors today; the annealing runtime intends to cover config and
aggregation, with the read-only catalog already projecting these leaves (see
[Attributed runtime flows](/design/config-anneal/execution-model0.gpt6.md)).

Native flow execution currently covers only `build`, `install`, and `status`.
The new config lane is inventoried as commands, with its generated root also
recorded as an action, but has no native config-flow projection. See the
[apt-client runtime alignment assessment](/design/runtime-config-lane/assessment0.gpt61sol.md)
for the verified gap and the distinction between domain actions and aggregates.

Where the omnibus runtime is present, `compfuzor-catalog.sh` provides read-only
inventory of attributed contributors, actions, commands, resource references,
and build/install/status flow order. Existing generated shell compositors remain
authoritative for execution while native composition is annealed.

Experimental deployments may set `RUNTIME_FLOW_EXECUTION: true` to add
`compfuzor-flow.sh` and make their validated catalog authoritative. Production
Zim and Mise do not opt in; `zim2.opt.pb` and `mise2.opt.pb` are contained
experiments.

Zim adds one complete domain command, `install-zim.sh`, because installing Zim
also means installing two loader blocks, building two caches, and maintaining a
host registry. Mise does not acquire a CONFIG graph: its Bash blocks remain
independent block-in-file installations, while its Zsh activation arrives via
Zim.

## What is healthy now

The live Zim and Mise deployments were rendered and activated on 2026-09-13.
CONFIG assembly/status, both Zim channels and caches, loader blocks, registry,
LINKS state, and Mise Bash blocks were clean. See the
[deployment log](/doc/config/log.md#vite-packaged-runtime-cutover) for evidence
and exact commands.

This does not mean the implementation is pleasantly small. The current system
works and has careful behavioral coverage, but some of its internal layering is
transitional. The [simplification plan](/doc/config/simplification.md) names
what should be deleted rather than celebrated.

## Design history

Current maintained behavior lives in this directory. Inquiry and implementation
checkpoints remain available for rationale:

- [Runtime resumption guide](/design/runtime-direction/index.md) — recovered
  recent intent, earlier roadmaps, adoption counterexamples, and the still-open
  composition/Effect direction; distinguishes proposals from shipped behavior.
- [Fixed CONFIG command](/design/config-context/command0.solx.md)
- [Command review corrections](/design/config-context/command0-review0.solx.md)
- [Systemd is not a CONFIG context](/design/install-context/systemd0.unknown.md)
- [Systemd/LINKS representations](/design/install-context/systemd-links0.solx.md)
- [Earlier config-user-target inquiry index](/.design/config-user-target/README.md)

Those files explain decisions; they are not the operator entry point.
