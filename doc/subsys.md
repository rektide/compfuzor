# Subsystem architecture

Compfuzor models each build/runtime tool as a **subsystem**: Go, Rust, Node.js, Bun, npm, CMake, Python, and kernel configuration. Each subsystem has a name, a set of environment variables that activate or bypass it, and a `contrib` payload (`BINS`, `ENV`, `PKGS`, `ETC_FILES`, `TOOL_VERSIONS`, etc.) that gets merged into the host config when active.

## What changed and why

Compfuzor originally used two Jinja2 filter plugins — `subsystem_bypassed` and `subsystem_record` — plus a set of `sub_*.tasks` files to assemble subsystem state at runtime. Each `sub_*` task computed `requested`, `bypassed`, `valid`, `active`, `status`, then used `subsystem_record` to build a dict, then published it to the `SUBSYSTEM` fact.

This had three problems:

1. **Ansible 2.20 broke cross-plugin imports.** Each filter plugin gets an isolated module namespace. `from _subsystem_utils import ...` fails at load time with a misleading traceback. The `sys.path` hack to work around it was fragile.

2. **Redundant computation.** Every `sub_*` task recomputed the same requested/bypassed/valid/active/status logic. The `subsystem_record` filter existed to avoid repeating this, but it depended on the broken cross-plugin import.

3. **Distributed definitions.** Subsystem data (bins, env, tool versions) was split between `vars/common.yaml` and individual `sub_*.tasks` files. Understanding what a subsystem contributes required reading multiple files.

The refactor consolidates everything into two places:

- **[`vars/common.yaml`](../vars/common.yaml#L174-L583)** — static `SUBSYSTEM` definitions containing only data (`contrib`, optionally `spec` and `requested`).
- **[`library/lookup_plugins/subsys.py`](../library/lookup_plugins/subsys.py#L205-L281)** — the `subsys` lookup that reads from `SUBSYSTEM` and derives the full state envelope (`requested`, `bypassed`, `active`, `valid`, `status`) at query time.

The `subsystem_bypassed` and `subsystem_record` filter plugins are gone. The old `sub_*` tasks for Go, Node.js, Bun, npm, Rust, CMake, Python, and repo_npm are gone because their data lives in [`common.yaml`](../vars/common.yaml#L174-L583). Runtime validation still uses task files where needed. For example, [`sub_get_urls.tasks`](../tasks/compfuzor/sub_get_urls.tasks#L1-L29) validates `GET_URLS`, while [`gen_kernel.tasks`](../tasks/compfuzor/gen_kernel.tasks#L1-L53) handles kernel validation and multi-child merging.

## The rule

A subsystem is **active** when:

1. Its trigger variable (`<NAME|upper>`) is truthy, AND
2. Its bypass variable (`<NAME|upper>_BYPASS`) is not truthy.

Some subsystems override `requested` with a Jinja expression (e.g. cmake checks `CMAKE or CMAKE_ARGS or CMAKE_BUILDS`). The lookup reads `record.get("requested")` first and falls back to checking the env var.

`valid` defaults to `true`. A static subsystem can set `valid` and `reasons`, but most current validation tasks fail fast before generation. The state computation path is in [`subsys.py`](../library/lookup_plugins/subsys.py#L118-L201).

## Static definitions in `vars/common.yaml`

Most subsystems are pure data. No task files needed.

```yaml
SUBSYSTEM:
  go:
    contrib:
      BINS:
        - name: build.sh
          run: "{{ BINS_RUN_BYPASS is not deftruthy }}"
          basedir: repo
          generated: |
            go build -o ${GO_BIN:-$TYPE} ${GO_TARGET:-./...}
      ENV:
        GO_BIN: "{{ GO_BIN | default(omit) }}"
      TOOL_VERSIONS:
        go: true

  cmake:
    requested: "{{ CMAKE is deftruthy or CMAKE_ARGS is defined or CMAKE_BUILDS is defined }}"
    contrib:
      BINS: "{{ _cmake_bins }}"
      PKGS: [cmake, ninja-build]
      ENV: "{{ _cmake_env }}"
```

The `subsys` lookup derives everything else when queried:

- `requested`: from the record's `requested` field, or from `<NAME|upper>` env var
- `bypassed`: from `<NAME|upper>_BYPASS`, optionally `<DOMAIN>_BYPASS` or extra vars
- `valid`: from the record's `valid` field, defaulting to `true`
- `active`: `requested and not bypassed and valid`
- `status`: one of `active`, `bypassed`, `invalid`, `requested`, `absent`

## Reading subsystem state with `lookup('subsys')`

The `subsys` lookup returns a normalized envelope for one subsystem. Use `get=` to extract a single field.

### Whole envelope

```yaml
- set_fact:
    go_subsys: "{{ lookup('subsys', id='go') }}"
```

Returns:

```yaml
id: go
name: go
status: active
active: true
requested: true
bypassed: false
valid: true
spec: []
contrib:
  BINS: [...]
  ENV: {...}
  TOOL_VERSIONS: {go: true}
```

### Single field

```yaml
- set_fact:
    go_active: "{{ lookup('subsys', id='go', get='active', default=false) }}"
```

### Nested field via dot path

```yaml
- set_fact:
    go_bins: "{{ lookup('subsys', id='go', get='contrib.BINS', default=[]) }}"
```

### Domain bypass (kernel example)

Kernel subsystems use domain-level bypass — setting `KERNEL_BYPASS` bypasses all kernel children:

```yaml
modprobe_bypassed: "{{ lookup('subsys', id='kernel_modprobe', domain='kernel', get='bypassed', default=False) | bool }}"
```

This checks both `KERNEL_MODPROBE_BYPASS` and `KERNEL_BYPASS`.

### Fallback id

For parametric subsystem resolution where the id might be undefined:

```yaml
with_items: "{{ lookup('subsys', id=subsystem_id, fallback_id='get_urls', get='spec') }}"
```

## The `gen_*.tasks` pattern

Each subsystem has a `gen_*.tasks` file that merges the subsystem's `contrib` into the host's `BINS`, `ENV`, `PKGS`, etc. Use `merge_subsys` for the common case. It reads `SUBSYSTEM.<id>.contrib.<artifact>`, merges it with the current global artifact, and skips inactive subsystems by default. The implementation and supported artifact defaults live in [`merge_subsys.py`](../library/lookup_plugins/merge_subsys.py#L109-L152).

The usual pattern is short:

```yaml
- name: "Compfuzor: synthesize go subsystem artifacts"
  set_fact:
    BINS: "{{ lookup('merge_subsys', id='go', contrib='BINS') }}"
    ENV: "{{ lookup('merge_subsys', id='go', contrib='ENV') }}"
    TOOL_VERSIONS: "{{ lookup('merge_subsys', id='go', contrib='TOOL_VERSIONS') }}"
  when: lookup('subsys', id='go', get='active', default=false) | bool
```

That is the full [`gen_go.tasks`](../tasks/compfuzor/gen_go.tasks#L1-L7) file. [`gen_nodejs.tasks`](../tasks/compfuzor/gen_nodejs.tasks#L1-L7) and [`gen_bun.tasks`](../tasks/compfuzor/gen_bun.tasks#L1-L7) use the same shape; [`gen_rust.tasks`](../tasks/compfuzor/gen_rust.tasks#L1-L8) also merges `PKGS`.

Use direct `merge_list` or `merge_dict` calls only when the subsystem needs custom behavior that `merge_subsys` does not expose. For example, [`gen_get_urls.tasks`](../tasks/compfuzor/gen_get_urls.tasks#L1-L7) merges only `BINS` from a local `_get_urls_contrib` value.

The `when` guard reads `active` from the lookup. If the subsystem isn't active, nothing happens.

## Worked example: `go`

The `go` subsystem is a good minimal model because it has static data only. It does not need runtime validation or a `sub_go.tasks` file.

### User input

A playbook activates the subsystem by setting the trigger variable:

```yaml
GO: true
```

Because `go` does not define a custom `requested` expression, the `subsys` lookup falls back to the `GO` variable. If `GO_BYPASS` is truthy, the subsystem is requested but inactive.

### Static subsystem data

The static definition lives under `SUBSYSTEM.go` in [`vars/common.yaml`](../vars/common.yaml#L208-L225):

```yaml
go:
  contrib:
    BINS:
      - name: build.sh
        run: "{{ BINS_RUN_BYPASS is not deftruthy }}"
        basedir: repo
        generated: |
          go build -o ${GO_BIN:-$TYPE} ${GO_TARGET:-./...}
      - name: install.sh
        basedir: repo
        generated: |
          [ -n "${INSTALL_BIN-}" ] || INSTALL_BIN="${GO_BIN:-$TYPE}"
          ln -sfv "$(pwd)/${INSTALL_BIN}" $GLOBAL_BINS_DIR/$(basename $INSTALL_BIN)
    ENV:
      GO_BIN: "{{ GO_BIN | default(omit) }}"
      GO_TARGET: "{{ GO_TARGET | default('./...') }}"
    TOOL_VERSIONS:
      go: true
```

This contributes two generated scripts, two environment defaults, and a `.tool-versions` entry. `TOOL_VERSIONS` is merged into the global `TOOL_VERSIONS` fact by `merge_subsys`; [`gen_tool_versions.tasks`](../tasks/compfuzor/gen_tool_versions.tasks#L1-L13) only renders that final fact into `.tool-versions` artifacts.

### Merge task

[`gen_go.tasks`](../tasks/compfuzor/gen_go.tasks#L1-L7) merges the active contribution into global facts:

```yaml
- name: "Compfuzor: synthesize go subsystem artifacts"
  set_fact:
    BINS: "{{ lookup('merge_subsys', id='go', contrib='BINS') }}"
    ENV: "{{ lookup('merge_subsys', id='go', contrib='ENV') }}"
    TOOL_VERSIONS: "{{ lookup('merge_subsys', id='go', contrib='TOOL_VERSIONS') }}"
  when: lookup('subsys', id='go', get='active', default=false) | bool
```

After this task runs, normal filesystem tasks create the bin files. `bins.tasks` sends contentful BINS through the [`files/_bin`](../files/_bin#L1-L32) template, as shown in [`bins.tasks`](../tasks/compfuzor/bins.tasks#L13-L28). That wrapper adds the shebang, shell options, env loading, default working directory, and the `generated` body.

### Include point

The include belongs in the variables phase because it only synthesizes facts. The existing import is in [`tasks/compfuzor.includes`](../tasks/compfuzor.includes#L67-L69):

```yaml
- import_tasks: compfuzor/gen_go.tasks
  when: GO is deftruthy
  tags: ['vars', 'always']
```

Subsystems that only add `BINS`, `ENV`, `PKGS`, `ETC_FILES`, or `TOOL_VERSIONS` usually belong in this phase. If a subsystem must inspect a checked-out repository, put that work after the repository phase instead. The git checkout happens in [`tasks/compfuzor.includes`](../tasks/compfuzor.includes#L85-L95), while bin files are materialized later in the filesystem phase at [`tasks/compfuzor.includes`](../tasks/compfuzor.includes#L100-L138).

## Contrib artifacts and merge behavior

`merge_subsys` supports these contrib artifacts by default. The source of truth is [`ARTIFACT_DEFAULTS`](../library/lookup_plugins/merge_subsys.py#L109-L152).

| Artifact | Kind | Default merge | Practical effect |
|----------|------|---------------|------------------|
| `BINS` | list | `bins_generated` | Merge entries by `name`; concatenate overlapping `generated` fields. |
| `ETC_FILES` | list | `append` | Current entries come first, subsystem entries append. |
| `LINKS` | list | `append` | Current entries come first, subsystem entries append. |
| `PKGS` | list | `append_unique` | Append subsystem packages and remove exact duplicates while preserving order. |
| `ENV_LIST` | list | `append_unique` | Append env names and remove exact duplicates while preserving order. |
| `ETC_DIRS` | list | `append` | Current entries come first, subsystem entries append. |
| `ENV` | dict | `env_overlay` with current wins | Subsystem defaults are added, but explicit playbook `ENV` values override them. |
| `TOOL_VERSIONS` | dict/list shorthand | `tool_versions_overlay` with current wins | Subsystem tool defaults are added; user mappings or list shorthand override them. |

`BINS` uses the named `bins_generated` profile from [`merge.py`](../library/filter_plugins/merge.py#L48-L54). That profile maps to `merge_keyed` by `name` and concatenates `generated`. The keyed merge behavior is implemented in [`merge.py`](../library/filter_plugins/merge.py#L212-L263). Generic list and dict merge behavior is in [`merge.py`](../library/filter_plugins/merge.py#L302-L353).

`TOOL_VERSIONS` uses the `tool_versions_overlay` dict strategy. It normalizes mappings and list shorthand through [`dictify`](../library/filter_plugins/dictify.py#L1-L53): mappings pass through, lists of strings become `{tool: true}`, lists of mappings overlay, and scalar values fail fast.

Use direct `merge_list` or `merge_dict` only when you need behavior outside this table.

## When you still need task logic

Most subsystems should be static data plus a small `gen_*.tasks` merge file. Add task logic only when data alone is not enough.

1. **Runtime validation.** [`sub_get_urls.tasks`](../tasks/compfuzor/sub_get_urls.tasks#L1-L29) validates that URL entries are strings or mappings with a non-empty `url`. It fails before `gen_get_urls.tasks` runs.

2. **Multi-child orchestration or custom merging.** [`gen_kernel.tasks`](../tasks/compfuzor/gen_kernel.tasks#L1-L53) validates shared kernel inputs, checks three child subsystem states, and merges their `BINS`, `ENV`, `ENV_LIST`, `ETC_FILES`, and `PKGS` contributions together.

If future task logic needs to affect `subsys` state instead of failing fast, publish a minimal record into `SUBSYSTEM` before the relevant `gen_*.tasks` import:

```yaml
subsystem:
  valid: "{{ _subsystem_valid }}"
  reasons: "{{ errors }}"
  spec: "{{ spec if (_subsystem_valid and _subsystem_requested) else [] }}"
```

The lookup wraps that record with the full envelope on read.

## The generic eval contract

`vars/common.yaml` defines control-flow variables used by validation and custom orchestration tasks:

```yaml
errorChecks: []
errors: "{{ errorChecks | selectattr('failed', 'truthy') | map(attribute='msg') | list }}"
_subsystem_requested: "{{ requested | default((items | default([], true) | arrayitize | length > 0), true) | bool }}"
_subsystem_bypassed: "{{ bypassed | default(lookup('subsys', id=subsystem_name | default(''), domain=subsystem_domain | default(none), bypass=subsystem_bypass_vars | default(none), get='bypassed', default=False), true) | bool }}"
_subsystem_valid: "{{ valid | default(errors | length == 0) | bool }}"
_subsystem_active: "{{ _subsystem_requested and (not _subsystem_bypassed) and _subsystem_valid }}"
```

Tasks set `subsystem_name` and optionally `subsystem_domain`, `errorChecks`, `requested`, `valid` as task-local vars. The contract derives `_subsystem_requested`, `_subsystem_bypassed`, `_subsystem_valid`, `_subsystem_active` for use in `when:` guards.

## Bypass variable resolution order

The `subsys` lookup checks bypass variables in this order:

1. `<SUBSYSTEM_ID|upper>_BYPASS` (e.g. `RUST_BYPASS`)
2. `<DOMAIN|upper>_BYPASS` if `domain=` is set (e.g. `KERNEL_BYPASS`)
3. Extra bypass vars from `bypass=` kwarg (string or list)

If any is truthy, `bypassed` is `true`.

## Adding a new subsystem

1. Add an entry to `SUBSYSTEM` in [`vars/common.yaml`](../vars/common.yaml#L174-L583). Set `requested` only if the trigger logic differs from `<NAME> is truthy`. Put contrib data under `contrib`.

2. Create a `gen_<name>.tasks` file following the pattern above — read from `lookup('subsys', id='<name>')`, guard with `get='active'`.

3. Add the `gen_*.tasks` import to [`tasks/compfuzor.includes`](../tasks/compfuzor.includes#L24-L80) with a `when:` guard matching the trigger condition. Put fact-only generation in the variables phase. Put work that depends on a checked-out repo after the repository phase at [`tasks/compfuzor.includes`](../tasks/compfuzor.includes#L85-L95).

4. If you need validation, add a task before generation. Prefer failing fast for invalid input, like [`sub_get_urls.tasks`](../tasks/compfuzor/sub_get_urls.tasks#L1-L29). If validation state must be visible through `lookup('subsys')`, publish a minimal record into `SUBSYSTEM` before the `gen_*.tasks` import.

### Minimal template

Use this shape for subsystems that only add files, bins, packages, links, or environment defaults:

```yaml
# vars/common.yaml
SUBSYSTEM:
  example:
    requested: "{{ EXAMPLE is deftruthy or EXAMPLE_ITEMS is defined }}"
    spec: >-
      {%- set normalized = [] -%}
      {%- for raw in EXAMPLE_ITEMS | default([]) | arrayitize -%}
        {%- set row = raw if raw is mapping else {'value': raw} -%}
        {%- set _ = normalized.append(row) -%}
      {%- endfor -%}
      {{ normalized }}
    contrib:
      BINS:
        - name: example.sh
          basedir: repo
          generated: |
            echo "example subsystem"
      ENV:
        EXAMPLE_VALUE: "{{ EXAMPLE_VALUE | default(omit) }}"
      PKGS: []
```

```yaml
# tasks/compfuzor/gen_example.tasks
---
- name: "Compfuzor: synthesize example subsystem artifacts"
  set_fact:
    BINS: "{{ lookup('merge_subsys', id='example', contrib='BINS') }}"
    ENV: "{{ lookup('merge_subsys', id='example', contrib='ENV') }}"
    PKGS: "{{ lookup('merge_subsys', id='example', contrib='PKGS') }}"
  when: lookup('subsys', id='example', get='active', default=false) | bool
```

Then import it from [`tasks/compfuzor.includes`](../tasks/compfuzor.includes#L24-L80):

```yaml
- import_tasks: compfuzor/gen_example.tasks
  when: EXAMPLE is deftruthy or EXAMPLE_ITEMS is defined
  tags: ['vars', 'always']
```

Keep the `gen_*.tasks` file boring. It should usually merge facts and nothing else.

### Generated script conventions

Generated `BINS` go through [`files/_bin`](../files/_bin#L1-L32). That wrapper already adds the shebang, `set -euo pipefail`, env loading, default `cd`, verbose tracing via `V`, and shell-option restoration. Generated bodies should focus on the subsystem work.

Common fields:

| Field | Use |
|-------|-----|
| `name` | Output filename under `BINS_DIR`. Also the merge key for `BINS`. |
| `generated` | Shell body generated from Jinja. Prefer this for subsystem-created scripts. |
| `content` | Literal shell body from a playbook. Useful for hand-written per-playbook bins. |
| `src` | Template or raw file from `files/<type>/...`. Use when the script is large or shared. |
| `basedir: repo` | Run from the checked-out repository via `cd {{ DIR }}/repo`. |
| `basedir: false` | Do not emit an automatic `cd`. Use this for scripts that manage paths explicitly. |
| `run: true` | Run the generated script during `bins_run.tasks`. Use sparingly. |
| `env: false` | Skip sourcing env files in the wrapper. Rarely needed. |

For scripts that operate on a checked-out repository, prefer `basedir: repo`. For scripts that download or prepare inputs outside the repo, use the default `$DIR` or set a specific `basedir`.

### Normalizing `spec`

Use `spec` when the playbook input can be shorthand. Normalize early so generated scripts can iterate one predictable shape.

For list input that accepts strings or mappings:

```yaml
spec: >-
  {%- set normalized = [] -%}
  {%- for raw in PR_PATCHES | default([]) | arrayitize -%}
    {%- set row = raw if raw is mapping else {'url': raw} -%}
    {%- set index = loop.index -%}
    {%- set _ = normalized.append({
      'index': index,
      'url': row.url,
      'name': row.name | default(row.url | basename),
    }) -%}
  {%- endfor -%}
  {{ normalized }}
```

Read the normalized value with:

```yaml
patch_specs: "{{ lookup('subsys', id='patches', get='spec', default=[]) }}"
```

Do validation in a task file if invalid input should produce a clear Ansible error. Static `spec` normalization is enough when missing fields will fail clearly in the generated script.

### Verification checks

Subsystem changes should verify the lookup behavior and at least one generated playbook path.

Useful checks:

```bash
pytest tests/lookup_plugins/subsys.test.py tests/lookup_plugins/merge_subsys.test.py
ansible-playbook handy.src.pb --syntax-check
```

When a subsystem adds a generated script, also inspect the rendered bin in the target directory or run the playbook against a safe target with `--check` if the tasks support check mode. If the subsystem depends on a checked-out repo, verify both a fresh checkout path and a rerun path.

## File map

| File | Purpose |
|------|---------|
| [`vars/common.yaml`](../vars/common.yaml#L174-L583) | Static `SUBSYSTEM` defs, helper vars, generic eval contract |
| [`library/lookup_plugins/subsys.py`](../library/lookup_plugins/subsys.py#L205-L281) | Lookup: resolves envelope from SUBSYSTEM + env vars |
| [`library/lookup_plugins/merge_subsys.py`](../library/lookup_plugins/merge_subsys.py#L109-L152) | Lookup: merges subsystem contrib artifacts into globals |
| [`library/filter_plugins/merge.py`](../library/filter_plugins/merge.py#L48-L58) | Direct list/dict merge helpers and named merge profiles |
| [`library/filter_plugins/dictify.py`](../library/filter_plugins/dictify.py#L1-L53) | Strict mapping/list-shorthand normalization for dict-like inputs |
| [`library/filter_plugins/build_install_bins.py`](../library/filter_plugins/build_install_bins.py#L6-L41) | `build_install_bins` filter (used by kernel) |
| [`tasks/compfuzor/sub_get_urls.tasks`](../tasks/compfuzor/sub_get_urls.tasks#L1-L29) | Validates `GET_URLS` before generation |
| [`tasks/compfuzor/gen_kernel.tasks`](../tasks/compfuzor/gen_kernel.tasks#L1-L53) | Validates and merges kernel child subsystems |
| [`tasks/compfuzor/gen_go.tasks`](../tasks/compfuzor/gen_go.tasks#L1-L7) | Minimal `gen_*.tasks` example using `merge_subsys` |
| [`tasks/compfuzor/gen_get_urls.tasks`](../tasks/compfuzor/gen_get_urls.tasks#L1-L7) | Custom merge example using `merge_list` |
