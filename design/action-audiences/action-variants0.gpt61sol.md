---
type: ResearchReport
title: Existing action aliases and audience selection
description: Verified precedents for symlink dispatch, context precedence and lexical invocation identity, plus gaps in deployment-wide audience defaults and .mts support.
resource: /design/action-audiences/action-variants0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-06 }
verified: { by: unverified }
sources:
  - resource: /files/install-zim.sh
    title: Preserve invoked basename before resolving the executable
  - resource: /files/zim/cli.ts
    title: Context-selecting installer aliases
  - resource: /files/config/invocation.ts
    title: Declared-name selection precedence
  - resource: /files/runtime/compfuzor-runtime.ts
    title: Shared multicall runtime and symlink-chain selection
  - resource: /library/filter_plugins/config_context_compile.py
    title: Generated fixed CONFIG action aliases
---

# Main finding

**The remembered prior work exists.** Zim has one installer that accepts
context-selecting symlink aliases. CONFIG generates fixed-action symlinks to
one shared multicall runtime. The exact deployment-wide arrangement—real file
names the default audience, other audience names and an unqualified name alias
it—is not implemented today.

This report synthesizes delegated source/history/live-layout research. The
parent additionally read the Zim shell entry, Zim alias selection, shared name
selection, CONFIG alias generation and multicall runtime. No tests were rerun
and no live deployment was changed for this inquiry.

# Reusable precedents

## Zim: one installer with context aliases

[`install-zim.sh`](/files/install-zim.sh#L6-L9) deliberately captures two paths:

```sh
invoked=$(basename "$0")
script=$(readlink -f -- "$0")
```

The first selects the variant; the second locates the implementation and its
deployment. [`aliasContext`](/files/zim/cli.ts#L118-L135) recognizes
`install-zim-CONTEXT.sh`. Aliases are manually created, not generated; the
[integration test](/tests/integration/zim_consumer.test.py#L665-L674) creates
`install-zim-system.sh -> install-zim.sh` and exercises the behavior.

[`resolveSelectedName`](/files/config/invocation.ts#L17-L28) supplies existing
precedence: **explicit option → invoked alias → environment → compiled
default**. It rejects undeclared contexts. Thus the prior interface already
allows an explicit context to override an audience-like alias; a new general
policy should deliberately preserve or revise this, not accidentally differ.

The delegated history trace identified the Zim installer checkpoint as
`33d2e21e5906` (September 11). Earlier explanation lives in
[the context-target inquiry](/.design/config-user-target/build5.solx.md).

## CONFIG: generated aliases into one runtime

[`config_context_compile.py`](/library/filter_plugins/config_context_compile.py#L260-L274)
generates six fixed action aliases:

```text
config-{install,assemble,sync-inputs,publish,inputs,status}.sh
    → config/command.mjs
    → compfuzor-runtime.mjs
```

These are symlinks, not separately built executable copies. The controller
claims one checked-in runtime artifact through
[`runtime_bundles.py`](/library/filter_plugins/runtime_bundles.py); aliases
materialize through [`bins_link.tasks`](/tasks/compfuzor/bins_link.tasks).

The [multicall selector](/files/runtime/compfuzor-runtime.ts#L37-L95) inspects
the unresolved invocation path and its symlink chain to find a recognized
domain. It separately resolves physical module identity and deployment location.
In Node the script invocation path is **`process.argv[1]`**, not `argv[0]`.

## Lexical identity must survive flow execution

The flow runtime validates physical containment but executes the lexical alias
path. This already fixed a real regression: resolving to the final target before
execution loses the invoked variant. See
[`flow/runtime.ts`](/files/flow/runtime.ts#L72-L86) and the
[alias regression test](/tests/integration/catalog_flow.test.py#L131-L146).
The history checkpoint is `b21779c589e5` (September 14).

Other narrow prior art is the repository's
[`pkg-install.sh`](/script/pkg-install.sh) alias to
[`pkg-check.sh`](/script/pkg-check.sh): the same script switches behavior from
its invoked basename.

# What is not already general

- **Bin composition** accepts per-leaf scopes, including lists, but normally
  emits separate system/default and user aggregates. It does not select scope
  from symlink identity or implement a central user-first default mode.
  See [`bin_composers.py`](/library/filter_plugins/bin_composers.py#L121-L209).
- **USERMODE** remains render-time defaults: directory relocation plus systemd
  policy. It does not rename bins by audience. Managed bins follow deployment
  `DIR`; `BINS_DIR` is deliberately not independently overridden. See
  [`vars_base.tasks`](/tasks/compfuzor/vars_base.tasks#L3-L17) and
  [`common.user.yaml`](/vars/common.user.yaml).
- **Context is not identical to audience or privilege.** Contexts can be named
  arbitrarily and carry roots and scope. Selecting system scope is not an
  instruction to run sudo. Existing CONFIG/Zim install leaves can default to
  user contexts while participating in an unscoped install aggregate.
- **Systemd has real operational differences** between user and system manager
  operations, already represented by dual/separate leaves. Aliasing the entry
  point must choose the correct plan, not execute an identical leaf body twice.
  See [`vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks#L378-L430).

The delegated live scan found many `.sh → .mjs` runtime aliases but no general
same-bin `.sh → .sh` audience family in the inspected deployments. That is
observational evidence, not a proof that no custom deployment has one.

# .mts is feasible, but not yet covered end to end

The delegated Node inspection found native TypeScript stripping on available
Node 26 and `.mts` mapped to module-TypeScript. No project `.mts` sources were
found. Direct file-based `.mts` invocation was **not tested**.

Three compatibility concerns remain:

1. [`package.json`](/package.json) still permits Node 20.19, which does not
   establish native `.mts` support. Deployment requirements must be decided,
   not inferred from the current workstation's newer Node.
2. [`tsconfig.json`](/tsconfig.json) uses `.ts` include globs; `.mts` needs
   explicit checking coverage.
3. [`compfuzor-runtime.ts`](/files/runtime/compfuzor-runtime.ts#L25-L47) and
   its deployment-root inference recognize existing `.mjs`/`.ts` names and
   layouts. Adding `.mts` entry points requires corresponding admission and
   packaging tests, not just a suffix change.

The [archive toolkit](/archive/README.md) already provides separate precedent
for a distributed `.ts` executable using Node's stripping, while the main
runtime is still bundled as `.mjs` targeting Node 20.19.

# Cross-references

- [Operator intent](/design/action-audiences/intent0.gpt61sol.md): the requested
  default-real-file arrangement is a broader evolution of these precedents.
- [CONFIG stages](/design/action-audiences/config-stages0.gpt61sol.md): action
  aliases must preserve the distinctions among assembly, delivery and install.
- [Fixed CONFIG command design](/design/config-context/command0.solx.md):
  explains the existing choice to avoid an action-by-context wrapper matrix.
- [Systemd context inquiry](/design/install-context/systemd0.unknown.md): prior
  tension between audience selection and manager-scope operational partition.
