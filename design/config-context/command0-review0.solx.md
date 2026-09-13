---
type: ArchitectureCheckpointReview
title: Fixed CONFIG command review corrections
description: Close strict transaction, bypass-boundary, aggregate Zim status, and byte-exact stdout regressions found after the fixed-action CONFIG checkpoint.
resource: /design/config-context/command0-review0.solx.md
tags: [compfuzor, config, contexts, transactions, bypass, status, zim, review]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-13 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-13 }
stale_after: 2026-10-13
sources:
  - id: reviewed-checkpoint
    resource: /design/config-context/command0.solx.md
    title: Fixed CONFIG actions over selected contexts
  - id: operator-guide
    resource: /doc/config/consumer-toolkit.md
    title: Consumer configuration toolkit
  - id: accepted-rescope
    resource: /.design/config-user-target/core-rescope0.unknown.md
    title: Core re-scope for contexts, commands, and complete installs
---

# Fixed CONFIG command review corrections

## Review outcome

Parent and independent review found four material regressions in the accepted
fixed-action implementation. All four are corrected without restoring wrapper
matrices, changing `$0` selection, migrating systemd, or introducing a general
plan engine:

1. The now-raw transaction runner is independently strict and fault-tested.
2. CONFIG bypass is an ordinary-install result, while internal machinery and
   explicit operator actions remain bypass-neutral.
3. Aggregate Zim status binds `--activation-only` as structured invocation
   metadata, so generic config candidates are evaluated once.
4. `--stdout` requires exactly one selected recipe and rejects before processor
   execution.

The review also confirmed runtime Zim bypass behavior explicitly: install and
producer import skip; status remains observable.

## 1. Strict standalone transaction runner

### Regression

`config_context_compile` internalized the formerly wrapped `config.sh` as raw
`config/run.sh`. The old `_bin` wrapper had supplied strict shell options, but
the source runner did not. A failed staging `cp`, `chmod`, or unguarded command
could therefore continue and reach output commit with incomplete state.

### Correction

[`config-run.sh`](/files/config-run.sh) now begins with:

```bash
set -euo pipefail
```

The strict-mode audit also changed behavior where a bare `set -e` was
insufficient or harmful:

- apply-selection and per-recipe input JSON are materialized through commands
  whose failures are observed, rather than unchecked process substitutions;
- processor and candidate validation remain explicit guarded failures;
- `cmp` and diagnostic `diff` non-match statuses are intentionally tolerated;
- candidate and staging copy/mode failures exit before any output move;
- output-move failure restores the current backup and every earlier output;
- rollback and trap cleanup are explicitly best-effort so one cleanup error
  cannot interrupt later restorations;
- success reporting happens only after every output commit and cannot interrupt
  the transaction.

### Fault evidence

[`config_transaction_faults.test.py`](/tests/integration/config_transaction_faults.test.py)
injects failures at:

| Failure point | Expected invariant |
|---|---|
| second selected processor | neither existing output changes |
| first staging `cp` | neither output changes; no candidate/backup remains |
| first staging `chmod` | neither output changes; no candidate/backup remains |
| second staged-output `mv`, after the first output committed | both prior output bytes are restored; no candidate/backup remains |

This preserves the existing multi-output rollback while proving the source file
is safe without `_bin` strict-mode assistance.

## 2. Bypass belongs to typed install

### Regression

CONFIG processor records retained subsystem bypass guards. Under
`COMPFUZOR_CONFIG_BYPASS`, a processor wrapper could return 0 without writing
its candidate. An unvalidated recipe could then stage and commit an empty file.
Meanwhile the config CLI itself handled bypass, so Zim's direct typed call did
not share the same policy.

### Corrected CONFIG boundary

`config/run.sh`, `config/processor.sh`, and processor-bound leaves are explicitly
bypass-neutral. They either perform their internal protocol or fail. The same
is true of direct fixed operator commands.

[`installContext`](/files/config/install.ts) is the sole runtime CONFIG bypass
boundary and returns a typed outcome:

```text
{status: completed, code}
{status: skipped, code: 0, reason}
```

Its strategy arguments are lazy. A bypassed install does not parse stale
install/input strategy environment values before returning skipped.

| Invocation under `COMPFUZOR_CONFIG_BYPASS=1` | Behavior |
|---|---|
| `config-install.sh` | skip success; no input/output mutation |
| Zim's typed CONFIG install | same typed skip outcome |
| `config-assemble.sh` | executes normally |
| `config-status.sh` | executes normally |
| explicit sync/publish/input operation | executes normally |
| internal processor protocol | executes normally; cannot fake an empty success |

`COMPFUZOR_CONFIG_CONTEXTS_BYPASS` has the same ordinary-install runtime
boundary. Generation-time context suppression remains separate.

### Zim handling of skipped CONFIG

Zim no longer equates CONFIG skip with completed config work:

1. If both selected `zimenv` and `zimrc` outputs resolve to regular files, the
   independent loader, cache, and registry work may continue using those known
   outputs.
2. If either output is unavailable, remaining Zim installation skips cleanly
   with a reason. It does not call Zsh against a nonexistent config.

This is deliberately not a force or recovery framework. It makes only the
minimum prerequisite check needed to keep a bypassed ordinary install safe.

### Zim domain bypass

`install-zim.sh` is raw, so annotation could never provide runtime guards.
`COMPFUZOR_ZIM_BYPASS=1` is now checked in the Zim dispatcher:

| Zim action | Behavior |
|---|---|
| install, direct or composed | skip before spec/context/strategy resolution |
| producer import | skip before mutation |
| status | always evaluate |

No new per-step Zim bypass variables were added. Generation-time `ZIM_BYPASS`
is unchanged.

## 3. One generic config evaluation in aggregate Zim status

### Regression

Direct `status-zim.sh` correctly became complete-install status, including
generic CONFIG health. Aggregate `status.sh` then invoked both
`config-status.sh` and complete `status-zim.sh`, evaluating every Zim config
candidate twice.

### Structured reporter invocation

The aggregate status record now permits fixed arguments:

```yaml
- name: status-zim.sh
  args: [--activation-only]
  exit2: error
```

[`status.sh`](/files/status/status.sh) constructs one safely quoted argument
array per reporter and invokes fixed arguments before caller arguments. Existing
string records bind no fixed arguments, still receive caller arguments, and
retain historical exit-2 not-applicable behavior. Structured `exit2: error`
still maps evaluation errors to aggregate attention.

The resulting boundaries are:

| Invocation | CONFIG | Zim activation |
|---|---:|---:|
| direct `status-zim.sh` | yes | loaders, caches, registry |
| direct `status-zim.sh --activation-only` | no | loaders, caches, registry |
| aggregate `status.sh` | once via `config-status.sh` | once via fixed Zim argument |

Clean and evaluation-error integration assertions count each `zimenv`/`zimrc`
assembly row exactly once in aggregate output. No status wrapper or context file
was added.

## 4. Byte-exact stdout is singular

### Regression

Multi-recipe stdout wrote a textual header and then each candidate as it was
built. That was neither a byte-exact CONFIG stream nor atomic with respect to a
later candidate failure.

### Corrected contract

`config-assemble.sh --stdout` must resolve to exactly one recipe:

| Selection | Result |
|---|---|
| one explicit recipe | raw candidate bytes, exit 0 |
| zero names and exactly one `apply: true` recipe | raw candidate bytes, exit 0 |
| zero names selecting zero or several recipes | error 2 before processor execution |
| several explicit names | error 2 before processor execution |

Both the public dispatcher and internal runner enforce the rule. The internal
fault test uses a processor marker to prove rejected stdout launches no
processor. All mutating actions, checks, publication, input synchronization,
and status retain zero/one/many recipe selection.

## Preserved architecture

- The public CONFIG surface remains exactly six fixed symlinks.
- User-created `config-CONTEXT-ACTION.sh` aliases and partial explicit override
  semantics are unchanged.
- `canonical` remains explicit and does not make source=destination delivery
  meaningful.
- CONFIG retains one assembly transaction and one processor family.
- Zim loader/cache/registry/import lifecycle remains domain-local.
- Safe copy/link, no-force, no-receipt, and no-prune behavior remains.
- No systemd migration, universal operation graph, live deployment, package
  installation, or push was performed.

The retained post-review scratch proof is
`.test-agent/config-contexts/zim-demo-v9a310y6/README.md`. It stays beneath a
fresh unique root and includes the corrected bypass and aggregate/direct status
exercise from the focused Zim integration.

## Verification scope

Focused verification includes:

- strict runner fault injection and cleanup;
- fixed command/context/strategy/alias precedence;
- CONFIG install skip, direct assemble/status, and internal processor behavior
  under CONFIG bypass;
- Zim config-bypass behavior with missing and existing outputs;
- direct/composed Zim domain bypass and observable status;
- structured status fixed arguments, string-record compatibility, and exit-2
  adaptation;
- direct complete and aggregate activation-only Zim status with one config
  evaluation;
- BINS/config/context/Zim filter tests, config remote routing, strict native
  TypeScript, Node/shell syntax, and playbook syntax.

## Remaining concerns

1. Rollback cleanup is best-effort if the filesystem also rejects restoration;
   warnings identify such failures, but no cross-filesystem journal is claimed.
2. Aggregate status remains a boolean attention result rather than exposing a
   structured top-level error code.
3. `--activation-only` is a supported direct diagnostic switch but is intended
   primarily as aggregate invocation metadata.
4. Existing deployed wrappers remain outside automatic pruning policy.

The next architectural activity remains a separate parent-reviewed systemd
comparison. This correction pass deliberately stops before that work.

## Cross-references

- [`command0.solx.md`](/design/config-context/command0.solx.md) is the reviewed
  implementation checkpoint; this document supersedes its stdout, bypass, and
  aggregate-status details without replacing the accepted fixed-action shape.
- [`consumer-toolkit.md`](/doc/config/consumer-toolkit.md) contains the corrected
  maintained operator contract.
- [`doc/bins.md`](/doc/bins.md) documents the narrow structured status invocation
  record alongside filename-independent action composition.
- [`build5-review0.solx.md`](/.design/config-user-target/build5-review0.solx.md)
  remains the baseline for Zim loader, alias, and contributor behavior.

# Addendum: Backup preallocation correction

Final independent review found one remaining allocation window in the commit
loop: backup `mktemp` calls occurred after earlier selected outputs could already
have been replaced. A later backup-allocation failure exited under strict mode
without calling `rollback_prior`.

The runner now reserves every required backup destination before its first
output mutation. Existing destinations receive `mktemp` placeholders, and the
later `mv` atomically replaces those placeholders with the prior outputs;
destinations absent at commit preparation require no backup. Every placeholder
is registered with transaction cleanup immediately. If any reservation fails,
all earlier placeholders and staged candidates are removed while every output
still has its original bytes.

Focused fault injection fails the second backup allocation for two existing
selected outputs and proves:

- both processors and staging execute only once;
- neither output changes;
- no candidate or backup placeholder remains.

The ordinary two-output success path and the existing later-move rollback case
also remain green. This invariant covers synchronous preparation and commit
failures exercised by the transaction; it does not claim atomic recovery from
uncatchable process termination or machine failure.
