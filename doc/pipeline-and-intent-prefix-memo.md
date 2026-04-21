# Pipeline Stage + Intent Prefix Memo

This memo defines the model we want compfuzor to converge on.

We separate two axes:

- pipeline stage: runtime execution order (when)
- intent prefix: meaning and contract (what)

The goal is to make layer authoring legible for both humans and agents.

## Pipeline Stage Comments To Add In `tasks/compfuzor.includes`

These are the stage comments we should add to the current include pipeline.

```yaml
# STAGE 1: COMPILE CONTEXT + ARTIFACTS
#   1A foundation (`vars_*`)
#   1B discovery (`probe_*`, when introduced)
#   1C transforms (`fn_*`, when introduced)
#   1D synthesis (`gen_*`, migrated from generative `vars_*`)

# STAGE 2: USER / EXECUTION CONTEXT

# STAGE 3: REPOSITORY APPLY (`repo_*`)

# STAGE 4: FILESYSTEM + SCRIPT APPLY (`fs_*`, `bins*`, `links*`)

# STAGE 5: DOMAIN APPLY EXTRAS (`apt`, `pkgs`, `pg`, `sysctl`, etc.)

# STAGE 6: POST-RUN HOOKS + THUNKS
```

Notes against the current file:

- stage 1 currently uses `vars_*` for multiple intents; we will split over time
- stage 4 already includes bins and links apply work and should be named as such
- stage 6 covers delayed link passes and legacy systemd thunk execution

## Intent Prefix Contract

We use intent prefixes in multiple scopes. The table below expands canonical
labels into explicit columns so docs and agents can parse them consistently.

Scoped label format:

- `intent:<file|data>`
- `kind:<vars|probe|fn|syn|repo|fs|bins|links|raw|norm|spec|drv|out|merge|tmp|...>`
- `form:<prefix|envelope|internal>`
- `class:<foundation|discovery|transform|synthesis|execution|orchestration|...>`
- `side-effect:<none|host|mixed>`
- apply family: `apply:<type|none>` (for example `apply:get-urls`)

The simple name comes from `class:*`.

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
|  |  |  |  |  |  |  |  |
| `raw_` | `intent:data` | `kind:raw` | `form:prefix` | `class:input` | `apply:none` | `side-effect:none` | data-prefix | unnormalized values |
| `norm_` | `intent:data` | `kind:norm` | `form:prefix` | `class:normalization` | `apply:none` | `side-effect:none` | data-prefix | validated/normalized values |
| `spec_` | `intent:data` | `kind:spec` | `form:prefix` | `class:model` | `apply:none` | `side-effect:none` | data-prefix | ordered domain table |
| `drv_` | `intent:data` | `kind:drv` | `form:prefix` | `class:derivation` | `apply:none` | `side-effect:none` | data-prefix | intermediate computed values |
| `out_` | `intent:data` | `kind:out` | `form:prefix` | `class:output` | `apply:none` | `side-effect:none` | data-prefix | completed transform payload |
| `merge_` | `intent:data` | `kind:merge` | `form:prefix` | `class:synthesis-input` | `apply:none` | `side-effect:none` | data-prefix | merge-ready payload |
| `syn_` | `intent:data` | `kind:syn` | `form:prefix` | `class:synthesis-output` | `apply:none` | `side-effect:none` | data-prefix | synthesized payload ready for pipeline merge |
| `_tmp_` | `intent:data` | `kind:tmp` | `form:internal` | `class:scratch` | `apply:none` | `side-effect:none` | data-prefix | short-lived local values (`visibility:internal`) |
|  |  |  |  |  |  |  |  |
| `_probe_<domain>` | `intent:data` | `kind:probe` | `form:envelope` | `class:discovery-envelope` | `apply:<domain>` | `side-effect:none` | data-envelope | probe handoff record |
| `_fn_<domain>_out` | `intent:data` | `kind:fn` | `form:envelope` | `class:transform-envelope` | `apply:<domain>` | `side-effect:none` | data-envelope | transform handoff record |
| `_syn_<domain>` | `intent:data` | `kind:syn` | `form:envelope` | `class:synthesis-envelope` | `apply:<domain>` | `side-effect:none` | data-envelope | synthesis handoff record |

## Preferred Authoring Flow Per Layer

For non-trivial behavior:

1. validate contract
2. normalize values (`norm_*`)
3. model with one ordered spec (`spec_*`)
4. derive outputs (`drv_*`, `out_*`)
5. prepare synthesis input (`merge_*`)
6. emit synthesis payload in `gen_*` (`syn_*` / `_syn_<domain>`), then merge into canonical pipeline artifacts
7. apply in execution stages (`repo_*`, `fs_*`, `bins*`, `links*`, extras)

## Open Design Item: `fn_multi`

`fn_multi` is a nice-to-have only if it stays explicit and contract-driven.

Minimum bar:

- declared input schema
- deterministic output names
- no hidden side effects
- wrappers allowed when generic shape hurts readability
