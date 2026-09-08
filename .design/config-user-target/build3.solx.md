---
type: ArchitectureCheckpoint
title: Zim consumer migration and Mise block status
description: Completed generic-to-Zim migration with direct donor baseline, consumer-local contribution, ordered activation, canonical registry, and focused Mise Bash status.
resource: /.design/config-user-target/build3.solx.md
tags: [compfuzor, config, zim, mise, consumer-context, links, block-in-file]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
stale_after: 2026-10-08
sources:
  - id: corrected-toolkit
    resource: /.design/config-user-target/build2-review0.solx.md
    title: Consumer config toolkit review corrections
  - id: zim-channels
    resource: /.design/zim-generator/channels1.gpt56s.md
    title: Dual Zim startup channels
---

# Zim consumer migration and Mise block status

## Outcome

Zim now uses the generic consumer context as its only user config assembler.
Canonical donor administration, consumer-local inputs, loader blocks, cache
activation, and host registry are separate operations. Mise gained only the
small fitting benefit: shared named-block status for its independent Bash
loaders. No live deployment, package installation, module fetch, or real user
startup file was touched.

## Zim topology

### Canonical host baseline

`zim_fragment` remains the single content renderer. Its host layout writes the
host's roster directly into:

```text
ETC/zimrc.d/<phase-name>.conf
ETC/zimrc.d/<phase-name>.conf.disabled
ETC/zimenv.d/<phase-name>.conf
ETC/zimenv.d/<phase-name>.conf.disabled
```

Nonhost contributors retain
`etc/zim/<channel>/{active,disabled}/`; local generated modules retain
`zim-modules/<name>/...`. Duplicate declarations that produce both active and
disabled forms of one channel filename fail during compilation. Existing stale
filesystem counterparts are not pruned; the generic donor status reports the
obvious conflict.

Because host fragments are ordinary `ETC_FILES`, normal filesystem rendering
populates the donor before the generated `config.sh` apply. Host user install no
longer self-promotes its roster.

### Canonical admin operation

```bash
/opt/zim-main/bin/install-zim-donor.sh /opt/producer
```

This is the explicit shared-roster operation. It uses canonical
`config-remote.ts` input mutation and reassembly, is `compose: false`, and never
builds user caches. `install-zim.sh` remains a compatibility symlink to the same
admin command; its role is no longer ambiguous.

### Consumer context

The host declares one context for both channels:

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user
    root: config
    subpath: zsh
    install: assemble
    dropins: link
    configs:
      zimrc:
        output: {env: ZIM_CONFIG_FILE, default: zimrc, ignore: [legacy canonical paths]}
      zimenv:
        output: {env: ZIM_ENV_CONFIG, default: zimenv, ignore: [legacy canonical paths]}
```

Inputs bind to `$XDG_CONFIG_HOME/zsh/{zimrc,zimenv}.d`; outputs default to
`$XDG_CONFIG_HOME/zsh/{zimrc,zimenv}`. `ZDOTDIR` independently selects `.zshrc`
and `.zshenv` loader destinations. Playbook defaults are
`ZIM_CONFIG_INSTALL=assemble` and `ZIM_CONFIG_DROPINS=link`; generic runtime
strategy selectors remain available.

The selector's small `ignore` list is migration-specific configuration, not a
global write policy. Exact inherited values equal to the old canonical
`ETC/{zimrc,zimenv}` paths fall back to local outputs. Truly custom overrides
remain authoritative. Loader, channel-builder, status, and generic context
resolution apply the same distinction. Deliberate donor following uses the
explicit whole-link command.

### Consumer-local producer import

Contributor `install-user-zimfw.sh` now discovers the host through:

1. `ZIM_HOST_DIR`;
2. `ZIM_CONFIG_LINK` or `$XDG_CONFIG_HOME/zsh/zimfw.conf`;
3. `/opt/zim-main`.

It never uses runtime `ZIM_CONFIG_FILE` for host identity. It invokes:

```bash
/opt/zim-main/bin/install-zim-context.sh /opt/producer
```

The host script inventories both channels before mutation, rejects a producer
active/disabled duplicate, and uses generic input `put --strategy link
--no-rebuild`. `--disabled` initializes a new disabled contribution without a
transient active assembly. Existing local enabled/disabled state wins on
reimport. After all puts, each touched channel is assembled once and its cache
is built once.

This operation changes only the invoking consumer. Promotion into the donor is
the separate admin command above.

### Install ordering

The generated user compositor was inspected and executed. Its order is:

```text
install-config-user.sh
install-zimenv-loader-user.sh
install-zimrc-loader-user.sh
install-zim-caches-user.sh
install-zim-registry-user.sh
```

The generic context dispatcher appears exactly once. Explicit whole/drop-in
strategy variants remain non-composed. Loader leaves use the `units` scheduling
lane; cache and registry leaves use `records`, preserving order even though
playbook-authored BINS precede generated config BINS before sorting.

### Loaders, caches, and registry

- `.zshenv` and `.zshrc` are independent `block-in-file` artifacts. Known old
  single-loader blocks are removed through `block-in-file --remove-match`, not
  copied `sed` parsing. Unmanaged startup text remains.
- `.zshenv` keeps an anonymous local Zim scope and removes its controller
  function. `.zshrc` establishes the ordinary global Zim context. Mise remains
  loaded only through `zimenv`.
- `zimfw-channel.sh` builds each cache from the resolved local config and
  respects truly custom `ZIM_ENV_CONFIG`/`ZIM_CONFIG_FILE` paths.
- `ZIM_CONFIG_LINK` remains independent canonical host evidence. A small
  runtime manifest lets the actual LINKS manager apply/status the selected XDG
  or explicit registry path; it always targets canonical `ETC/zimrc`.
- `status-zim.sh` is registered with the generic status orchestrator. It reports
  local cache freshness, two loader blocks through `block-in-file --read`, and
  canonical registry health. Generic context status separately owns
  input/assembly/output health.

## Generic additions made for the migration

- Input `put` accepts `--no-rebuild` and `--disabled`. These are bounded import
  controls, not a general batch transaction.
- Runtime output selectors may declare exact ignored legacy values.
- Captured config-runner mode closes stdin while piping stdout/stderr. This was
  required for CLI processors that inspect stdin and is covered by the real
  block-in-file integration.
- Combined context status accepts a healthy whole copy/link in a fresh home as
  an installed alternative. Missing local inputs and failed assembly evaluation
  become visible `inactive` observations only when **all** local input paths are
  absent. `config-user.sh --check` and `config-inputs-user.sh status` remain
  strict; initialized/partial assembly routes retain real failures.

## Mise result

Mise declares no `CONFIG_CONTEXTS`. Its Zsh behavior benefits through Zim's
`zimenv` channel. Its existing Bash installer still inserts two independent
blocks and its `install-user.sh` still owns the separate settings action.

The small shared [`block-status.sh`](/files/block-status.sh) helper runs
`block-in-file --read`, then compares the exact managed projection to its
source. Zim uses it for `.zshenv`/`.zshrc`; Mise's registered
`status-mise-bash.sh` uses it for `.bashrc`/`.bash_profile`. No block graph,
ETC_FILES target system, or duplicate block parser was introduced.

## Operator commands

The durable command reference and daily workflow are in
[`consumer-toolkit.md`](/doc/config/consumer-toolkit.md). Zim-specific entry
points are:

```text
install-user.sh                         complete ordered user setup
install-zim-donor.sh PRODUCER_DIR       explicit canonical admin promotion
install-zim-context.sh PRODUCER_DIR     current-consumer contribution import
install-zim{env,rc}-loader-user.sh      independent loader block installs
install-zim-caches-user.sh              build both local channel caches
install-zim-registry-user.sh            canonical registry via LINKS
status-zim.sh                           loaders, caches, registry
```

Generic config commands continue to provide assembly, status, drop-in
copy/link, input toggles, and whole-output copy/link.

## Verification

The main isolated proof executes the actual `zim.opt.pb` with package/download
work disabled and a local stub controller:

```bash
python3 tests/integration/zim_consumer.test.py
```

It verifies fresh render and rerender, direct host baseline, deliberate stale
precursor retention, read-only donor inputs, inherited canonical env values,
two independent users, custom output/registry paths, consumer-only producer
import, copy/link mixtures, disabled selection preservation, one build per
touched channel, loader projections/unmanaged text, no `.zshenv` leakage,
registry identity, whole copy/link and return to assembly, generic status, and
loader/source drift.

To preserve a complete runnable scratch deployment for inspection:

```bash
COMPFUZOR_KEEP_ZIM_DEMO=1 \
  python3 tests/integration/zim_consumer.test.py
# inspect .test-agent/config-contexts/zim-demo/
```

Other passing checks:

```text
zim_fragment tests                         81 passed
shared delivery + LINKS pytest             9 passed
config compiler/context/toolkit integrations passed
canonical Zim donor promotion integration  passed
Mise Bash block integration                passed
existing config graph/config-remote         passed
Zim and Mise Ansible syntax checks          passed
Bash, Node syntax, Python compile            passed
```

Native TypeScript checking remains isolated under
`.test-agent/config-contexts/typecheck/`:

```bash
cd .test-agent/config-contexts/typecheck
pnpm exec tsgo -p tsconfig.json
```

It passes with strict, noEmit, NodeNext, `allowImportingTsExtensions`, and
`isolatedDeclarations`. No project manifest changed.

## Tradeoffs and remaining limitations

- Stale canonical fragments and old contributor staging directories are never
  pruned. Active/disabled collisions are reported for deliberate repair.
- Canonical admin promotion retains config-remote's per-fragment rebuild
  behavior. It is explicit and correct but not batched.
- Consumer import is intentionally Zim-specific orchestration over generic
  no-rebuild puts, not a new generic transaction language.
- `--disabled` controls only a new input's initial state; an existing local
  selection deliberately wins.
- The registry uses an invocation-local LINKS manifest so arbitrary runtime
  `ZIM_CONFIG_LINK` works. It receives actual LINKS safety/status behavior but
  does not become a static claim in the deployment's `links.json` audit.
- Legacy normalization recognizes the known exact canonical spellings. Other
  custom paths remain custom by design.
- Cache freshness remains timestamp-based Zim application status; config status
  remains byte/content based.
- No production deployment was exercised. Independent review should inspect
  generated command naming, phase use, dynamic registry manifest tradeoff, and
  the bounded generic `put` options before live adoption.

## Cross-references

- [`zim.opt.pb`](/zim.opt.pb) is the migrated host declaration and activation
  flow.
- [`gen_zim.tasks`](/tasks/compfuzor/gen_zim.tasks) separates host direct layout
  from contributor consumer import.
- [`install-zim-context.sh`](/files/install-zim-context.sh) is the bounded
  per-producer consumer importer.
- [`install-zim.sh`](/files/install-zim.sh) is now canonical-admin only.
- [`zim_consumer.test.py`](/tests/integration/zim_consumer.test.py) is the
  runnable actual-playbook proof.
- [`mise_blocks.test.py`](/tests/integration/mise_blocks.test.py) proves the
  intentionally small Mise integration.
- [`build2-review0.solx.md`](/.design/config-user-target/build2-review0.solx.md)
  records the approved operational direction implemented here.
