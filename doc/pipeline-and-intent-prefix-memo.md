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

We use intent prefixes in multiple scopes. The `labels` column is the stable
classification key we can reuse in docs, reviews, and agent prompts.

| Prefix | Scope | Intent Class | Labels | Typical Output | Side Effects |
|---|---|---|---|---|---|
| `vars_` | file | foundation | `file, foundation, compile` | normalized base facts | no |
| `probe_` | file | discovery | `file, discovery, compile` | `_probe_<domain>` snapshot | no |
| `fn_` | file | transform | `file, transform, compile` | reusable output bundle(s) | no |
| `gen_` | file | synthesis | `file, synthesis, compile` | merged pipeline artifacts | no host apply |
| `repo_` | file | execution | `file, execution, apply, repo` | checked-out/updated repos | yes |
| `fs_` | file | execution | `file, execution, apply, filesystem` | files/dirs/downloads/env files | yes |
| `bins` / `bins_*` | file | execution | `file, execution, apply, bins` | managed scripts linked/run | yes |
| `links` / `links_*` | file | execution | `file, execution, apply, links` | symlinks | yes |
| `_*.tasks` | file | orchestration | `file, orchestration, internal` | fanout/control-flow only | depends |
| `raw_` | data | input | `data, input` | unnormalized values | n/a |
| `norm_` | data | normalization | `data, normalize` | validated/normalized values | n/a |
| `spec_` | data | model | `data, spec` | ordered domain table | n/a |
| `drv_` | data | derivation | `data, derived` | intermediate computed values | n/a |
| `out_` | data | output | `data, output` | completed transform payload | n/a |
| `merge_` | data | synthesis-input | `data, merge` | merge-ready payload | n/a |
| `syn_` | data | synthesis-output | `data, synthesis` | synthesized payload ready for pipeline merge | n/a |
| `_tmp_` | data | scratch | `data, scratch, internal` | short-lived local values | n/a |
| `_probe_<domain>` | data | envelope | `data, envelope, discovery` | probe handoff record | n/a |
| `_fn_<domain>_out` | data | envelope | `data, envelope, transform` | transform handoff record | n/a |
| `_syn_<domain>` | data | envelope | `data, envelope, synthesis` | synthesis handoff record | n/a |

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
