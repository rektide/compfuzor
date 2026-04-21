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

Scoped labels are first-class metadata for both scopes:

- `intent:<file|data>`
- `kind:<vars|probe|fn|syn|repo|fs|bins|links|raw|norm|spec|drv|out|merge|tmp|...>`
- `form:<prefix|envelope|internal>`
- `class:<foundation|discovery|transform|synthesis|execution|orchestration|...>`
- `side-effect:<none|host|mixed>`
- `apply:<type|none>` (for example `apply:get-urls`)

Simple labels (like `foundation` or `execution`) come from `class:*`.

Prefix contracts are in one merged table with the entity pattern first.

| Entity Pattern | Intent | Kind | Form | Class | Apply | Side Effect | Section | Typical Output |
|---|---|---|---|---|---|---|---|---|
| `vars_` | `intent:file` | `kind:vars` | `form:prefix` | `class:foundation` | `apply:none` | `side-effect:none` | file-prefix | normalized base facts |
| `probe_` | `intent:file` | `kind:probe` | `form:prefix` | `class:discovery` | `apply:none` | `side-effect:none` | file-prefix | `_probe_<domain>` snapshot |
| `fn_` | `intent:file` | `kind:fn` | `form:prefix` | `class:transform` | `apply:none` | `side-effect:none` | file-prefix | reusable output bundle(s) |
| `gen_` | `intent:file` | `kind:syn` | `form:prefix` | `class:synthesis` | `apply:none` | `side-effect:none` | file-prefix | synthesized pipeline payloads and artifact merges |
| `repo_` | `intent:file` | `kind:repo` | `form:prefix` | `class:execution` | `apply:repo` | `side-effect:host` | file-prefix | checked-out/updated repos |
| `fs_` | `intent:file` | `kind:fs` | `form:prefix` | `class:execution` | `apply:filesystem` | `side-effect:host` | file-prefix | files/dirs/downloads/env files |
| `bins` / `bins_*` | `intent:file` | `kind:bins` | `form:prefix` | `class:execution` | `apply:bins` | `side-effect:host` | file-prefix | managed scripts linked/run |
| `links` / `links_*` | `intent:file` | `kind:links` | `form:prefix` | `class:execution` | `apply:links` | `side-effect:host` | file-prefix | symlinks |
| `_*.tasks` | `intent:file` | `kind:orchestrator` | `form:internal` | `class:orchestration` | `apply:orchestration` | `side-effect:mixed` | file-prefix | fanout/control-flow helper behavior |
|  |  |  |  |  |  |  |  |  |
| `raw_` | `intent:data` | `kind:raw` | `form:prefix` | `class:input` | `apply:none` | `side-effect:none` | data-prefix | unnormalized values |
| `norm_` | `intent:data` | `kind:norm` | `form:prefix` | `class:normalization` | `apply:none` | `side-effect:none` | data-prefix | validated/normalized values |
| `spec_` | `intent:data` | `kind:spec` | `form:prefix` | `class:model` | `apply:none` | `side-effect:none` | data-prefix | ordered domain table |
| `drv_` | `intent:data` | `kind:drv` | `form:prefix` | `class:derivation` | `apply:none` | `side-effect:none` | data-prefix | intermediate computed values |
| `out_` | `intent:data` | `kind:out` | `form:prefix` | `class:output` | `apply:none` | `side-effect:none` | data-prefix | completed transform payload |
| `merge_` | `intent:data` | `kind:merge` | `form:prefix` | `class:synthesis-input` | `apply:none` | `side-effect:none` | data-prefix | merge-ready payload |
| `syn_` | `intent:data` | `kind:syn` | `form:prefix` | `class:synthesis-output` | `apply:none` | `side-effect:none` | data-prefix | synthesized payload ready for pipeline merge |
| `_tmp_` | `intent:data` | `kind:tmp` | `form:internal` | `class:scratch` | `apply:none` | `side-effect:none` | data-prefix | short-lived local values (`visibility:internal`) |
|  |  |  |  |  |  |  |  |  |
| `_probe_<domain>` | `intent:data` | `kind:probe` | `form:envelope` | `class:discovery-envelope` | `apply:<domain>` | `side-effect:none` | data-envelope | probe handoff record |
| `_fn_<domain>_out` | `intent:data` | `kind:fn` | `form:envelope` | `class:transform-envelope` | `apply:<domain>` | `side-effect:none` | data-envelope | transform handoff record |
| `_syn_<domain>` | `intent:data` | `kind:syn` | `form:envelope` | `class:synthesis-envelope` | `apply:<domain>` | `side-effect:none` | data-envelope | synthesis handoff record |

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
