# Intent Prefix System Memo

This memo captures the design we arrived at for compfuzor naming and structure.

The goal is simple: make it obvious where new behavior belongs, what each task
file is allowed to do, and how data should flow through the pipeline.

## Why This Exists

`tasks/compfuzor.includes` currently mixes different kinds of work under
`vars_*.tasks`: base defaults, host probing, reusable transforms, and full
artifact generation.

That works, but it hides intent. We want explicit intent so humans and agents
can extend compfuzor without guessing.

## Core Distinction: Stage vs Intent

There are two independent axes:

- **Pipeline stage**: runtime execution order (`variables`, `repositories`,
  `filesystem`, `extras`) in `tasks/compfuzor.includes`.
- **Intent prefix**: what kind of work a file or fact represents.

Do not conflate them. Stage is when. Intent is what.

## Intent Prefix System

We use intent prefixes at two scopes.

### 1) File Intent Prefixes

These classify `tasks/compfuzor/*.tasks` files.

- `vars_` - foundational defaults and normalization
- `probe_` - host/runtime discovery snapshots
- `fn_` - reusable transforms (contract in, structured output out)
- `gen_` - synthesis of pipeline artifacts (`BINS`, `ETC_FILES`, `ENV`,
  `ENV_LIST`, `PKGS`, `LINKS`)
- `repo_` - repository execution/apply operations
- `fs_` - filesystem execution/apply operations
- `bins*` - managed script install/link/run lifecycle
- `links*` - symlink lifecycle
- `_*.tasks` - internal orchestration helpers

### 2) Data Intent Prefixes

These classify facts created inside `set_fact`.

- `raw_` - input as supplied
- `norm_` - validated/normalized input
- `spec_` - ordered declarative model/table
- `drv_` - derived intermediate values
- `out_` - completed transform output
- `merge_` - prepared merge payload
- `syn_` - synthesis output payload
- `_tmp_` - local scratch

Recommended cross-file envelope names:

- probe snapshot: `_probe_<domain>`
- function output: `_fn_<domain>_out`
- synthesis handoff bundle: `_syn_<domain>`

Important: the data-intent prefixes are primary semantics. Envelope naming is a
transport shape for passing data between files.

## Synthesis Terminology

Use:

- `gen_` as the file prefix
- `synthesis` as the intent class concept

This keeps filenames short and practical while retaining a precise conceptual
term in docs.

## Mutation Contract

- `vars_`, `probe_`, `fn_` should not directly apply host-side side effects.
- `fn_` should usually produce output bundles first, then let `gen_` merge
  canonical pipeline artifacts.
- `gen_` performs in-memory synthesis into pipeline artifacts.
- `repo_`, `fs_`, `bins*`, `links*`, and domain executors perform host-side
  apply work.
- Prefer one explicit merge block over many tiny `set_fact` mutations.

## Authoring Pattern

Default recipe for non-trivial subsystem work:

1. validate contract
2. normalize input
3. build ordered spec table
4. derive outputs from spec
5. synthesize merge payload
6. apply in execution stages

This pattern keeps behavior deterministic and readable.

## Config / URLs / Systemd Seams

### Config

Split into:

- `fn_config.tasks` for parameterized config assembly
- `gen_config.tasks` for default batteries-included behavior

`gen_config` can preserve compatibility for simple `CONFIG_KEY` usage while
`fn_config` supports multi-config schemes.

### GET_URLS

Split into:

- `fn_get_urls.tasks` for spec normalization
- `gen_get_urls.tasks` for default helper synthesis (for example `get-urls.sh`)

Execution stays in `fs_get_urls.tasks`.

### Systemd

Make probe first-class:

- `probe_systemd.tasks` for discovery snapshot
- `gen_systemd.tasks` (and related unit synthesis) for generated artifacts

This removes ambiguity around old `vars_systemd` intent.

## Notes on `fn_multi`

General-purpose `fn_multi` may be useful, but only if contract-driven and
explicit. It should not become hidden magic.

If introduced, require:

- declared input schema
- deterministic output names
- no hidden side effects
- domain-specific wrappers where clarity would otherwise suffer

## What Success Looks Like

When this system is working, a new contributor or agent can answer quickly:

- where do I put this logic?
- what facts should I name and export?
- what file is allowed to merge artifacts?
- what stage actually applies host changes?

That is the intended end state.
