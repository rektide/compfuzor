---
type: ArchitectureAssessment
title: Apt-client configuration and the transitional runtime flow model
description: The apt-cacher config lane is a valid domain action but expands legacy composition outside the runtime's current flow and argument contracts.
resource: /design/runtime-config-lane/assessment0.gpt61sol.md
tags: [config, runtime, composition, apt-cacher-rs, flows]
status: draft
generated: { by: 'model:openai/gpt-6.1-sol', at: '2026-09-29' }
sources:
  - resource: /apt-cacher-rs.src.pb
    title: Apt-cacher daemon and per-client snippet declarations
  - resource: /library/filter_plugins/bin_composers.py
    title: Legacy compositor action classification
  - resource: /library/filter_plugins/runtime_catalog.py
    title: Catalog projection and three supported flows
  - resource: /files/flow/runtime.ts
    title: Opt-in runtime execution and descriptor-fixed arguments
  - resource: /design/config-anneal/execution-model0.gpt6.md
    title: Previously annealed contributor, action, invocation, and flow model
---

# Situation

The operator asks whether the recent config support for `apt-cacher-rs.src.pb`
fits the `runtime/` work or mixes old and new execution models badly. Two commits
matter: `dd0d9a07` added `config` to the generic shell compositor action set;
`4ff3de4b` added per-client apt snippet generation and remote installation.

The question is architectural alignment, not a request to rewrite or deploy
anything. The assessment uses current source, the live apt-cacher catalog and
generated compositor, and a side-effect-free compiler probe.

# Verdict

**There is real orchestration skew, but the apt domain behavior itself is not
the problem.** Shell leaves and external providers can legitimately remain
behind runtime actions. The mistake would be treating a new shell lane as an
extension of the shared runtime model when classification, flow membership,
arguments, and execution authority do not match.

The new lane works under legacy execution and has focused composer tests.
It is not a demonstrated production failure. It does, however, grow the
compatibility machinery that the annealed model intended to replace.

# Three meanings of configuration

| Meaning | Current owner | Apt-cacher example |
|---|---|---|
| Declared deployment files | Ansible filesystem materialization | Daemon `apt-cacher-rs.conf` and static local `30proxy` in `ETC_FILES` |
| Consumer configuration recipes/contexts | CONFIG domain in the shared multicall runtime | Fixed assemble/install/input/publication/status interface; not used for this dynamic client roster |
| Operator-triggered domain generation | Authored executable, currently composed through Bash | `config-30proxy.sh HOST...` discovers/selects clients and stages one file per client |

These are related, not identical. A hostname is an input to the apt-client
domain action; it does not automatically need to become a generic CONFIG
context. Conversely, the word `config` in a filename does not put the action
inside CONFIG's recipe/context implementation.

# Actual execution path

```text
BINS config-30proxy.sh
    -> bin_composers: filename-derived config action
    -> generated bin/config.sh
    -> forwards the same operator argv to each composing leaf
    -> apt-client host discovery/selection and output-path rule
    -> external block-in-file provider with envsubst
    -> staged ETC/30proxy.<host>

direct client-install.sh HOST
    -> optionally generate missing staged snippet
    -> scp / ssh / sudo install on selected client
```

[`config-30proxy.sh`](/files/apt-cacher-rs/config-30proxy.sh) reuses
`block-in-file` for substitution and managed-block writing, rather than building
a competing template engine. [`client-install.sh`](/files/apt-cacher-rs/client-install.sh)
is deliberately `compose: false`, keeping remote installation out of the
ordinary local aggregate. Both choices preserve useful domain distinctions.

# Verified mismatches

## The supported action/flow sets have diverged

- [`bin_composers.py`](/library/filter_plugins/bin_composers.py), line 22,
  recognizes `build`, `install`, `apply`, **and `config`**.
- [`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py), lines
  16–28 and 251–273, infers leaf actions without `config` and projects only
  build/install roots plus status reporters into flows.
- [`catalog/runtime.ts`](/files/catalog/runtime.ts), lines 36–53 and 153–160,
  validates indexed files only for build/install/status.
- [`flow/runtime.ts`](/files/flow/runtime.ts), lines 40–69, accepts only those
  same three flow names.

The generated `config.sh` has explicit `action: config`, so it **does** appear
as an action. Its leaf `config-30proxy.sh` appears as a command but is not
filename-classified as a config action. Neither gets a native config-flow
invocation. Command inventory is not equivalent to native execution support.

A compiler probe passed the apt-style two BINS records through the real
`bin_composers` and `compile_runtime_catalog`, with execution enabled:

```text
generated compositor: config.sh -> [config-30proxy.sh]
catalog action: command:config.sh, action=config, legacy exec handler
catalog flow names: build, install, status
config flow: absent
execution authority: catalog
```

Thus toggling `RUNTIME_FLOW_EXECUTION` cannot migrate this lane by itself.
The actual deployed apt-cacher catalog also records the three commands but only
those three flows; its authority remains `legacy-shell` and its only resource
contract is LINKS, not CONFIG. No live generation or remote install was run.

## Arguments differ, not just flow names

The live apt-cacher `bin/config.sh` forwards `"$@"` to its leaf. Its interface
includes arbitrary host selections, `host=proxy`, discovery, and proxy defaults.
The runtime flow interface takes one flow name and executes descriptor-fixed
`invoke.args`; it has no operator-argument forwarding to domain actions.

Adding `config` to three allowlists would therefore not make
`config.sh dynabook` equivalent to a native flow. A coherent implementation
needs an explicit account of operator inputs and which action receives them.
Blindly forwarding the same host arguments to every future config leaf would
create a fragile aggregate interface.

## Namespace and authority remain transitional

The composer relies on CONFIG's fixed commands carrying `compose: false` or an
explicit `action: install` to keep them out of the new lane. Tests cover this;
it is not presently accidental double execution. But filename grammar and
exceptions now carry more architectural responsibility.

The earlier [execution model](/design/config-anneal/execution-model0.gpt6.md)
separates command availability, action ownership, explicit invocations, and flow
participation. Extending name-derived wrapper synthesis instead does not advance
that separation. Initial native coverage was deliberately only three flows;
absence of `apply` is also pre-existing, not a new apt-cacher regression.

# Direction worth preserving

Keep the apt-client behavior and the external provider. Do not assume changing
Bash to TypeScript, adding a seventh dispatcher branch, or turning every client
into a CONFIG context would solve the orchestration mismatch.

The preferable convergence target is:

1. An explicitly owned apt-client action with an understood input interface;
   the existing script can be its exec adapter initially.
2. Explicit invocation/composition records rather than deriving participation
   solely from `config-*` names.
3. One shared description consumed by the legacy compatibility renderer and
   native catalog, with execution authority chosen deliberately.
4. Keep generation/staging distinct from remote delivery. Reuse CONFIG's
   assembly/publication facilities only where the actual resource semantics fit.

There are two reasonable scopes for a next change, neither yet authorized:

- **Compatibility-only:** keep the current direct domain action and shell
  aggregate, clearly labelled outside native flow support. Avoid further generic
  orchestration growth until the input/composition contract is decided.
- **Runtime convergence:** decide whether configuration generation merits a
  first-class flow, define its operator-input contract, and cover classification,
  catalog projection, indexed-file validation, execution, and compatibility
  together. Merely teaching the native runner another name is insufficient.

The consequential decision is **domain action versus aggregate flow**, not
which language executes the leaf. Parameterized apt-client generation may be
best retained as a direct action even if an explicitly bound invocation can also
participate in an aggregate.

# Cross-references

- [Configuration overview](/doc/config/README.md): maintained distinction between
  fixed CONFIG actions and the authored config compositor lane; this assessment
  identifies the native-flow limitation more precisely.
- [Contributed flows and execution policy](/design/config-anneal/execution-model0.gpt6.md):
  design direction separating action, invocation, and composition, against which
  the new filename-based lane should be judged.
- [Simplification tactical assessment](/design/config-anneal/simplification-assessment0.gpt6.md):
  explains why one bundled artifact is deployment simplification, not by itself
  a simpler domain model or a reason to erase domain ownership.
- [Configuration deployment log](/doc/config/log.md#experimental-catalog-flow-authority):
  documents that the current native runner deliberately consumes fixed arguments
  and has experimental, opt-in authority.
- [Composer tests](/tests/filter_plugins/bin_composers.test.py): prove lane
  grouping, fixed CONFIG-command exclusion, and explicit-action precedence, but
  do not establish native config-flow parity.
