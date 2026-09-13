# Configuration

Compfuzor compiles configuration declarations on the Ansible controller, then
installs a small built runtime that can assemble, publish, inspect, and update
configuration for a selected consumer context.

## Start here

- [Consumer configuration toolkit](/doc/config/consumer-toolkit.md) — current
  commands, contexts, copy/link choices, Zim workflow, and status semantics.
- [Simplification plan](/doc/config/simplification.md) — candid account of the
  remaining accidental complexity and the deletion-oriented route out.
- [Deployment log](/doc/config/log.md) — exact live render, activation, status,
  Vite+ packaging, and retained migration residue.

## Mental model

```text
playbook declarations
    |
    |  Python filter plugins (Ansible controller only)
    v
config.spec.json / zim.spec.json / links.json
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

- [Fixed CONFIG command](/design/config-context/command0.solx.md)
- [Command review corrections](/design/config-context/command0-review0.solx.md)
- [Systemd is not a CONFIG context](/design/install-context/systemd0.unknown.md)
- [Systemd/LINKS representations](/design/install-context/systemd-links0.solx.md)
- [Earlier config-user-target inquiry index](/.design/config-user-target/README.md)

Those files explain decisions; they are not the operator entry point.
