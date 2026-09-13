---
type: ArchitectureCheckpoint
title: Fixed CONFIG actions over selected contexts
description: Replace generated context and strategy wrappers with one multicall dispatcher, deep typed operations, explicit defaults, and filename-independent BINS composition.
resource: /design/config-context/command0.solx.md
tags: [compfuzor, config, contexts, bins, zim, status, multicall]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-13 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-13 }
stale_after: 2026-10-13
sources:
  - id: accepted-rescope
    resource: /.design/config-user-target/core-rescope0.unknown.md
    title: Core re-scope for contexts, commands, and complete installs
  - id: build5-review
    resource: /.design/config-user-target/build5-review0.solx.md
    title: Build 5 context semantics review
  - id: operator-guide
    resource: /doc/config/consumer-toolkit.md
    title: Consumer configuration toolkit
---

# Fixed CONFIG actions over selected contexts

## Outcome

CONFIG now has a small fixed public vocabulary instead of a Cartesian wrapper
surface:

```text
config-install.sh
config-assemble.sh
config-sync-inputs.sh
config-publish.sh
config-inputs.sh
config-status.sh
```

These six files are symlinks to one parser/selector at
[`config/command.ts`](/files/config/command.ts). They differ only through the
unresolved `$0`, which selects a known action. Context, recipe subset, and
copy/link strategy remain runtime choices. Compfuzor generates no context
aliases.

The parser is intentionally thin. It delegates to typed modules for assembly,
input synchronization and mutation, whole-output publication, installation,
and status. Zim calls those typed operations directly. The existing processor
leaves and one transaction runner remain the only assembly implementation.

## Public and internal shape

```text
bin/
├── config-{install,assemble,sync-inputs,publish,inputs,status}.sh
│   └── symlink -> config/command.ts
├── config/
│   ├── command.ts          action/context/option parsing and dispatch
│   ├── invocation.ts       import-safe declared-name precedence
│   ├── context.ts          runtime selector expansion and recipe binding
│   ├── install.ts          complete ordinary CONFIG install
│   ├── assembly.ts         temporary binding + transaction invocation
│   ├── inputs.ts           input catalog, sync, mutation, input status
│   ├── publication.ts      whole-output copy/link
│   ├── status.ts           representation-aware context status
│   ├── report.ts           CONFIG row rendering and 0/1/2 reduction
│   ├── run.sh              sole build/validate/atomic commit runner
│   ├── processor.sh        shared processor protocol
│   └── processors/*        processor-bound executable leaves
└── internal/config/*       recipe-to-processor symlinks
```

Removed source facades `config-context.ts` and `config/toolkit.ts` no longer
compete as public interfaces. There is no public `config.sh`; canonical assembly reaches the same
internal runner through `config-assemble.sh --context canonical`.

## Executable selection truth tables

### Action

| Explicit `--action` | recognized `$0` action | result |
|---|---|---|
| set | any, stale, or unknown | explicit action; alias action is not parsed |
| absent | exactly one | inferred action |
| absent | none or ambiguous | evaluation error (2) |

There is no environment or compiled default action. Ordinary entry is through a
fixed action symlink.

### Context

| Explicit `--context` | recognized alias context | domain env | generic env | compiled default | result |
|---|---|---|---|---|---|
| set | any, stale, or unknown | any | any | any | explicit context; alias context is not parsed |
| absent | set | any | any | any | alias context |
| absent | absent | set | any | any | `COMPFUZOR_CONFIG_CONTEXT` |
| absent | absent | absent | set | any | `COMPFUZOR_CONTEXT` |
| absent | absent | absent | absent | set | spec `defaultContext` |

The selected value must be declared. Zim uses the same
[`resolveSelectedName`](/files/config/invocation.ts) function with its own alias
grammar, `COMPFUZOR_ZIM_CONTEXT`, and compiled default.

### Manual CONFIG aliases

The accepted exact grammar is `config-CONTEXT-ACTION.sh`. The parser recognizes
a declared context and one fixed action. A user may point the alias through the
fixed symlink or directly at `config/command.ts`.

| Invocation | Explicit flags | result |
|---|---|---|
| `config-system-assemble.sh` | none | system + assemble |
| same | `--context user` | user + assemble |
| `config-system-status.sh` | `--action assemble` | system + assemble |
| `config-system-hostile.sh` | `--action assemble` | system + assemble; hostile action piece bypassed |
| `config-hostile-assemble.sh` | `--context system` | system + assemble; hostile context piece bypassed |
| unsupported basename | both `--action assemble --context system` | succeeds; alias parsing fully bypassed |
| unsupported basename | either flag missing | fails |

No filename infers copy/link strategy.

### Action-local settings

| Action/effect | Explicit | environment | compiled context |
|---|---|---|---|
| install mode | `--strategy` | `COMPFUZOR_CONFIG_INSTALL_STRATEGY` | `install` |
| install input strategy | `--dropins` | `COMPFUZOR_CONFIG_DROPINS_STRATEGY` | `dropins` |
| input sync / put | `--strategy` | `COMPFUZOR_CONFIG_DROPINS_STRATEGY` | `dropins` |
| publication | `--strategy` | `COMPFUZOR_CONFIG_PUBLISH_STRATEGY` | none |

Settings are resolved lazily. Copy/link install does not inspect an unused input
strategy; status does not inspect either install setting.

## Config spec v2 and defaults

[`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
now records:

```json
{
  "version": 2,
  "defaultContext": "user",
  "installOwner": "config",
  "contexts": {
    "user": { "scope": "user", "configs": {} },
    "canonical": { "scope": "system", "canonical": true, "configs": {} }
  }
}
```

`CONTEXT_DEFAULT` is globally `user`; `CONFIG_CONTEXT` and `ZIM_CONTEXT`
default to it and can be independently overridden. A declared-context plan
fails compilation if its domain default is absent. A context-free CONFIG plan
uses only `canonical` and does not compose ordinary consumer installation.

The reserved canonical context contains explicit path selectors for every
original recipe input and output. It does not reinterpret external paths or map
them through magic. Only assembly and status are accepted because sync,
publication, mutation, and ordinary install have no meaningful source/
destination relationship there.

## Multiple recipes and transactions

Zero positional recipe names selects all `apply: true` recipes under the chosen
context. One or many names selects exactly that subset. The assembly operation
passes the entire selected list into [`config-run.sh`](/files/config-run.sh).
The runner builds and validates every candidate privately before staging or
committing any output; a late selected validation failure leaves earlier
outputs unchanged.

Input `list` and `status` accept zero or many recipe names. Mutation subactions
retain `CONFIG/INPUT` selectors and are not conflated with recipe selection.

## BINS and complete installs

[`bin_composers.py`](/library/filter_plugins/bin_composers.py) accepts explicit
recognized `action` metadata independent of filename while preserving existing
filename discovery. The `config-install.sh` symlink declares
`action: install`, so bare `install.sh` invokes it directly once. It is not put
in a user lane merely because the compiled default context is user.

`CONFIG_INSTALL_OWNER` positively chooses which domain contributes ordinary
config setup. Its default is `config`; `zim.opt.pb` sets `zim`. The Zim compiler
rejects a host whose config spec is not Zim-owned, preventing duplicate
composition. `install-zim.sh` itself is unscoped and joins bare `install.sh` for
both user and system defaults. Contributor `install-zimfw.sh` retains its
domain-specific user scope.

This is not a command-plus-arguments graph. `$0` already carries CONFIG's fixed
action, so explicit action metadata is the smallest required BINS extension.

## Status contract

Direct `config-status.sh` and `status-zim.sh` preserve 0 clean, 1 drift, and 2
evaluation error. Zim status now includes generic health for its referenced
config context before checking both loaders, caches, and registry.

Aggregate status accepts a structured reporter record
`{name, exit2: error}`. Existing string reporters retain historical exit-2
not-applicable behavior, while CONFIG and Zim errors mark aggregate attention.
No per-context status adapter is generated and direct diagnostics are not
collapsed.

## Preserved behavior

- Seed preserves local entries, disabled state, edits, and extras.
- Refresh may replace regular files/symlinks without force ceremony.
- Whole publication accepts copy or link and refuses directories/special files.
- Equivalent physical symlink referents remain healthy.
- Parent-directory aliases into canonical inputs/outputs remain hazards.
- No automatic prune, ownership receipt, strategy database, implicit sudo, or
  cross-domain rollback framework was added.
- Zim loader projection, cache builds, registry, producer protocol, and
  contributor behavior remain domain-local.

## Verification evidence

Focused checks cover:

- BINS explicit action compatibility and validation;
- config/context/Zim compiler normalization and collisions;
- six generated symlinks exactly once with no context/strategy wrappers;
- symlink-chain, direct-target, hostile-alias, env, compiled-default, and
  explicit-flag precedence;
- two contexts and three recipes across zero/one/multiple selections;
- selected-set validation atomicity;
- copy/link defaults, environment, and explicit overrides;
- permissive delivery/status and alias-hazard behavior;
- config remote and canonical toggle rebuild routing;
- Zim user/system install, status, loader, cache, registry, donor, import, and
  contributor behavior;
- direct status error 2 and aggregate attention;
- strict isolated native TypeScript, shell syntax, focused integrations, and
  Zim playbook syntax.

No package installation, live deployment, push, prune, or full repository sweep
belongs to this checkpoint.

The retained fresh scratch proof is
`.test-agent/config-contexts/zim-demo-7recfuje/README.md`. It uses only paths beneath its unique test root and documents current fixed
CONFIG commands, user/system Zim status, and the one manually created Zim
context alias.

## Remaining risks and next comparison

1. `CONFIG_INSTALL_OWNER` is a small compile-time ownership scalar, not a
   generalized action registry. Another complete-install adopter must choose a
   distinct value and validate its own ownership.
2. Aggregate status remains boolean at the top level even though it no longer
   loses reporter error classification. A deployment-wide structured report is
   intentionally deferred.
3. Existing rendered deployments retain old wrappers because Compfuzor does not
   prune. Live migration needs a deliberate stale-file procedure.
4. The config spec is versioned but structurally validated by compiler/runtime
   checks rather than a separate JSON Schema.

The next architectural checkpoint should compare systemd without migrating it:

- Can one fixed systemd install command select user/system directly while its
  existing domain installer still owns link, daemon-reload, enable, and start?
- Does explicit BINS `action` metadata remove any wrapper solely used for
  composition?
- Are its status and privilege boundaries genuinely compatible with the shared
  selected-name resolver, or should they remain generated bindings?

Do not extract a universal install plan unless that comparison finds matching
inputs, failures, ordering, and recovery semantics.

## Cross-references

- [`core-rescope0.unknown.md`](/.design/config-user-target/core-rescope0.unknown.md)
  identified selected invocation and filename-independent composition as the
  two justified core seams; this checkpoint implements the accepted fixed
  action variation of that direction.
- [`build5-review0.solx.md`](/.design/config-user-target/build5-review0.solx.md)
  defines the Zim alias, loader, contributor, and user/system behavior retained
  here.
- [`consumer-toolkit.md`](/doc/config/consumer-toolkit.md) is the maintained
  operator guide and old-to-new command mapping.
- [`doc/bins.md`](/doc/bins.md) documents explicit action metadata alongside
  backward-compatible filename discovery.
- [`doc/subsys.md`](/doc/subsys.md) places the BINS change in the subsystem
  generation pipeline.
