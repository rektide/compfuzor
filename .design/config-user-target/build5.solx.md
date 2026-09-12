---
type: ArchitectureCheckpoint
title: Context-aware Zim installation surface
description: Replace context-specific Zim install leaves and generated aliases with one declared-context dispatcher, while preserving generic config tools and explicit donor roles.
resource: /.design/config-user-target/build5.solx.md
tags: [compfuzor, config, zim, contexts, aliases, links, verification]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-11 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-11 }
stale_after: 2026-10-11
sources:
  - id: previous-checkpoint
    resource: /.design/config-user-target/build4.solx.md
    title: Final consumer-config safety and integration review
  - id: user-guide
    resource: /doc/config/consumer-toolkit.md
    title: Consumer configuration toolkit
  - id: final-review
    resource: /.design/config-user-target/review-final0.unknown.md
    title: Final independent review before the dispatcher refactor
---

# Context-aware Zim installation surface

## Outcome

Zim now has one ordinary installation implementation for every declared
activation context:

```text
install-zim.sh --context NAME [--install assemble|copy|link] [--dropins copy|link]
```

The selected context receives one complete operation: config installation,
both loader blocks, both caches, and the canonical registry link. The checked-in
default remains `user`, donor drop-ins still default to `link`, and context
selection never invokes or implies `sudo`.

No playbook targeted live paths; no package manager, `/opt/zim-main` deployment,
user profile, prune operation, or privilege escalation was run.

## Architecture

### Activation declarations over config bindings

[`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
now accepts `CONFIG_CONTEXTS.<name>.compose`. A Zim-owned config context sets it
to `false`: its generic installer remains available to operators but cannot
also join package composition.

[`zim_context_compile.py`](/library/filter_plugins/zim_context_compile.py)
compiles a small activation declaration over those existing bindings. It:

- requires both `zimrc` and `zimenv` in the referenced config context;
- requires that context to have `compose: false`;
- records context scope, loader root, two cache homes, and registry destination;
- supplies concise HOME/XDG-aware defaults only for user scope;
- requires all four activation destinations explicitly for system scope;
- rejects invalid names, role-name collisions (`donor`, `context`), command
  collisions, unknown bindings, and inconsistent scope;
- emits no command aliases.

The generated spec is version 2. Its canonical record explicitly carries
`zimrcLegacy`, `zimenvLegacy`, `zimrcLoaderTemplate`,
`zimenvLoaderTemplate`, and `emergencyModule`; the runtime does not derive these
inputs from sibling paths. Version 1 is rejected with rerender guidance.

The checked-in declaration is intentionally small:

```yaml
ZIM_CONTEXT: user
ZIM_CONTEXTS:
  user:
    config: user
```

The resulting `etc/zim.spec.json` is inspectable and contains all runtime
activation selectors without duplicating `CONFIG_CONTEXTS` input/output
bindings.

### One domain runtime

[`zim/install.ts`](/files/zim/install.ts) owns selected-context install, status,
and producer import. It reuses:

- [`config/context.ts`](/files/config/context.ts) to resolve the exact context's
  `zimrc` and `zimenv` outputs;
- [`config/toolkit.ts`](/files/config/toolkit.ts) for assemble/copy/link and
  drop-in behavior;
- the stable `bin/links.ts` manager for registry apply/status;
- the existing canonical controller and independent Zim channels for cache
  builds.

Explicit resolved strategy fields were added to the toolkit options so the Zim
runtime can apply its already-resolved precedence without mutating process
environment.

### Composition ownership

The default context's scope determines the package lane, while the executable
surface stays context-independent:

```text
default user:   install-user.sh -> install-zim.sh exactly once
default system: install.sh      -> install-zim.sh exactly once
```

Neither compositor separately calls `install-config-<context>.sh`. All nine
generic config wrappers per context remain directly available: assembly, the
ordinary installer, three drop-in variants, two whole-output variants, input
operations, and status.

## Alias decision

Compfuzor generates only the base `install-zim.sh`. There is no alias map,
optional alias declaration, alias BINS record, or materialized alias symlink.

The base shell wrapper captures `basename "$0"` before `readlink -f`. A user may
therefore create a symlink manually using exactly:

```text
install-zim-<declared-context>.sh -> install-zim.sh
```

Only the context is inferred. Strategy tokens and Cartesian names are not
supported. An unsupported basename or undeclared context fails with guidance.
When `--context` is present, alias inference is skipped entirely, so that
explicit flag also overrides an unsupported or undeclared invoked basename.
The tested precedence is independent per setting:

| Setting | Precedence |
|---|---|
| context | `--context` > supported invoked alias > `COMPFUZOR_ZIM_CONTEXT` > compiled `ZIM_CONTEXT` |
| config install | `--install` > `COMPFUZOR_ZIM_INSTALL_STRATEGY` > `COMPFUZOR_CONFIG_INSTALL_STRATEGY` > context default |
| drop-ins | `--dropins` > `COMPFUZOR_ZIM_DROPINS_STRATEGY` > `COMPFUZOR_CONFIG_DROPINS_STRATEGY` > context default |

The old ambiguous donor-admin `install-zim.sh` alias is gone. Canonical donor
administration is only `install-zim-donor.sh`; consumer import remains
`install-zim-context.sh`.

## Exact generated Zim surface

Activation compilation adds exactly:

```text
etc/zim.spec.json
bin/install-zim.sh
bin/status-zim.sh
bin/zim/install.ts
```

The host separately retains two explicit noncomposed role commands:

```text
bin/install-zim-donor.sh
bin/install-zim-context.sh
```

The shared LINKS runtime is infrastructure reused by Zim, not another Zim
installer. A base render has no generated context alias and no
`install-zim-user.sh`, `zimfw-channel.sh`, `zim-registry.sh`, or context-specific
loader/cache/registry leaves.

The existing `etc/zimenv.zsh` and `etc/zimrc.zsh` host artifacts are now
specialized two-channel loader templates. They are not additional installer
commands.

## Preserved behavior and safety

- Canonical donor administration and consumer-local producer import remain
  separate operations.
- Contributor packages expose scope-neutral `install-zimfw.sh`; explicit
  `scope: [user]` metadata composes it into their `install-user.sh`.
- Contributor import assembles and builds each touched channel once.
- Runtime config output overrides and legacy canonical-value normalization are
  still handled by the generic context resolver.
- Physical canonical alias protection and no-prune behavior remain in the
  generic config toolkit.
- The registry still uses stable LINKS semantics with `--sudo never`.
- Loader blocks retain independent names and legacy block normalization.
- A foreign or missing ambient `DIR` cannot redirect generated compositors or
  the Zim dispatcher away from its own deployment.
- Mise behavior is unchanged.

## Status

`status-zim.sh [--context NAME]` resolves the same activation declaration as
install. It checks both cache/config pairs, both named loader blocks, and the
selected registry destination. It returns the aggregate status contract's
clean/drift result rather than exposing internal diagnostic exit codes.

## Explicit system-context proof

The integration fixture renders `user` and a second `system` declaration over
the same implementation. The system declaration supplies absolute config,
loader, cache, and registry paths. Tests prove:

- whole-copy and local-assembly strategies both work;
- old `COMPFUZOR_CONFIG_*_STRATEGY` environment names remain effective;
- a manually created context alias beats a conflicting environment context;
- explicit CLI context and strategies beat that alias and the environment;
- both caches, both loaders, registry, and context-aware status use the system
  declaration;
- a hostile `sudo` shim is never called.

The checked-in loader templates are projected by one specialized renderer.
Safely quoted selected-context config/cache values become the installed
defaults, while `ZIM_HOME`, `ZIM_ENV_HOME`, `ZIM_CONFIG_FILE`, and
`ZIM_ENV_CONFIG` remain runtime overrides. User and system loader blocks work
with those variables unset. `zimenv` remains anonymous and leaks no Zim
globals; `zimrc` retains ordinary global values and emergency behavior. Status
uses the same projection as install rather than comparing against template
bytes.

## Verification

The post-review verification and corrected loader-source proof are recorded in
[`build5-review0.solx.md`](/.design/config-user-target/build5-review0.solx.md).

Focused final verification is preserved under:

```text
.test-agent/config-contexts/build5-verification/README.md
.test-agent/config-contexts/build5-verification/summary.tsv
.test-agent/config-contexts/build5-verification/logs/
```

All 13 checks passed:

| Area | Check |
|---|---|
| composition | `tests/filter_plugins/bin_composers.test.py` |
| config compiler | `tests/filter_plugins/config_context_compile.test.py` |
| Zim compiler | `tests/filter_plugins/zim_context_compile.test.py` |
| runtime bundles | `tests/filter_plugins/runtime_bundles.test.py` |
| config contexts | `tests/integration/config_contexts.test.py` |
| config toolkit | `tests/integration/config_context_toolkit.test.py` |
| LINKS | `tests/integration/links.test.py` and `links_status.test.py` |
| Mise | `tests/integration/mise_blocks.test.py` |
| deployment identity | `tests/integration/orchestrator_identity.test.py` |
| donor administration | `tests/integration/zim_remote.test.py` |
| dual-context Zim lifecycle | `tests/integration/zim_consumer.test.py` |
| TypeScript | strict native `tsgo -p tsconfig.json` in the isolated scratch package |

`ansible-playbook zim.opt.pb --syntax-check`, Node syntax checks, and shell
syntax checks also passed. A full repository sweep was intentionally not run;
the requested regression surface is focused on config, composition, LINKS,
Zim, and Mise.

## Retained demo

The current post-validation proof is:

```text
/home/rektide/src/compfuzor/.test-agent/config-contexts/zim-demo-k960e_e3
```

Its `README.md` maps canonical, user, system, and producer paths. Its
`user-one.sh`, `user-two.sh`, and `system.sh` wrappers clear inherited Zim
context/strategy/output/bypass values before running generated commands. The
host's retained `install-zim-system.sh` is a manual test-created symlink; the
test first proves that rendering emitted no alias.

Examples:

```bash
demo=/home/rektide/src/compfuzor/.test-agent/config-contexts/zim-demo-k960e_e3
"$demo/user-one.sh" "$demo/zim host with spaces/bin/status.sh"
"$demo/system.sh" "$demo/zim host with spaces/bin/status-zim.sh"
"$demo/system.sh" "$demo/zim host with spaces/bin/install-zim-system.sh" \
  --install assemble --dropins copy
```

No wrapper sources a live profile, and every writable path stays under the demo
root.

## Scope preservation

The pre-existing uncommitted `files/config-remote.ts`,
`library/filter_plugins/config_compile.py`, `jujutsu.src.pb`, and
`termctrl.src.pb` work remains uncommitted and was excluded from every commit in
this build. Unrelated apt, mkosi, OpenCode, watchman, gmellon, and concurrent Zim
module-history commits were not rewritten or discarded.

## Cross-references

- [`consumer-toolkit.md`](/doc/config/consumer-toolkit.md) is the operator-facing
  declaration, precedence, command, and safety guide.
- [`build4.solx.md`](/.design/config-user-target/build4.solx.md) records the
  safety invariants and shared LINKS groundwork preserved here.
- [`review-final0.unknown.md`](/.design/config-user-target/review-final0.unknown.md)
  is the independent review preceding this narrower install-surface revision.
- [`zim_consumer.test.py`](/tests/integration/zim_consumer.test.py) is the
  rendered user/system, manual-alias, donor, contributor, and foreign-DIR proof.
- [`zim_context_compile.test.py`](/tests/filter_plugins/zim_context_compile.test.py)
  covers normalization, executable-set stability, required explicit system
  fields, ownership, reserved names, and collisions.
