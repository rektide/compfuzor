# Subsystem architecture

Compfuzor models each build/runtime tool as a **subsystem**: Go, Rust, Node.js, Bun, npm, CMake, Python, and kernel configuration. Each subsystem has a name, a set of environment variables that activate or bypass it, and a `contrib` payload (BINS, ENV, PKGS, ETC_FILES, TOOL_VERSIONS) that gets merged into the host config when active.

## What changed and why

Compfuzor originally used two Jinja2 filter plugins — `subsystem_bypassed` and `subsystem_record` — plus a set of `sub_*.tasks` files to assemble subsystem state at runtime. Each `sub_*` task computed `requested`, `bypassed`, `valid`, `active`, `status`, then used `subsystem_record` to build a dict, then published it to the `SUBSYSTEM` fact.

This had three problems:

1. **Ansible 2.20 broke cross-plugin imports.** Each filter plugin gets an isolated module namespace. `from _subsystem_utils import ...` fails at load time with a misleading traceback. The `sys.path` hack to work around it was fragile.

2. **Redundant computation.** Every `sub_*` task recomputed the same requested/bypassed/valid/active/status logic. The `subsystem_record` filter existed to avoid repeating this, but it depended on the broken cross-plugin import.

3. **Distributed definitions.** Subsystem data (bins, env, tool versions) was split between `vars/common.yaml` and individual `sub_*.tasks` files. Understanding what a subsystem contributes required reading multiple files.

The refactor consolidates everything into two places:

- **`vars/common.yaml`** — static `SUBSYSTEM` definitions containing only data (`contrib`, optionally `spec` and `requested`).
- **`library/lookup_plugins/subsys.py`** — the `subsys` lookup that reads from `SUBSYSTEM` and derives the full state envelope (`requested`, `bypassed`, `active`, `valid`, `state`) at query time.

The `subsystem_bypassed` and `subsystem_record` filter plugins are gone. The `sub_*` tasks for Go, Node.js, Bun, npm, Rust, CMake, Python, and repo_npm are gone — their data lives in `common.yaml`. Only `sub_get_urls` and `sub_kernel` remain as tasks because they have runtime validation or multi-child orchestration that can't be expressed statically.

## The rule

A subsystem is **active** when:

1. Its trigger variable (`<NAME|upper>`) is truthy, AND
2. Its bypass variable (`<NAME|upper>_BYPASS`) is not truthy.

Some subsystems override `requested` with a Jinja expression (e.g. cmake checks `CMAKE or CMAKE_ARGS or CMAKE_BUILDS`). The lookup reads `record.get("requested")` first and falls back to checking the env var.

`valid` defaults to `true`. The `sub_get_urls` and `sub_kernel` tasks publish `valid: false` with `reasons` when validation fails.

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
- `state`: one of `active`, `bypassed`, `invalid`, `requested`, `absent`

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
found: true
state: active
active: true
requested: true
bypassed: false
valid: true
reasons: []
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

Each subsystem has a `gen_*.tasks` file that merges the subsystem's `contrib` into the host's `BINS`, `ENV`, `PKGS`, etc. The pattern is consistent:

```yaml
- name: "Compfuzor: synthesize go subsystem artifacts"
  set_fact:
    BINS: "{{ merged.BINS }}"
    ENV: "{{ lookup('subsys', id='go', get='contrib.ENV') | combine(existingEnv) }}"
  when: lookup('subsys', id='go', get='active', default=false) | bool
  vars:
    existingEnv: "{{ ENV if ENV is mapping else {} }}"
    merged: >-
      {{ [
        {'BINS': BINS | default([])},
        {'BINS': lookup('subsys', id='go', get='contrib.BINS', default=[])}
      ] | merge_with_strategy({'BINS': {'op': 'merge_keyed', 'key': 'name', 'concat_fields': ['generated']}}, include_aggregate=false) }}
```

The `when` guard reads `active` from the lookup. If the subsystem isn't active, nothing happens.

## When you still need a `sub_*` task

Two cases require a task file:

1. **Runtime validation.** `sub_get_urls` validates that URL entries are well-formed strings or mappings with a `url` key. It publishes `valid` and `reasons` into the `SUBSYSTEM` record, and the lookup respects those fields.

2. **Multi-child orchestration.** `sub_kernel` manages four subsystems (`kernel_modprobe`, `kernel_sysctl`, `kernel_sysfs`, `kernel_all`) with shared validation, aggregate bins/env, and a rollup of child contrib payloads.

In both cases, the task publishes a minimal record into `SUBSYSTEM` via `set_fact`:

```yaml
subsystem:
  valid: "{{ _subsystem_valid }}"
  reasons: "{{ errors }}"
  spec: "{{ spec if (_subsystem_valid and _subsystem_requested) else [] }}"
```

The lookup wraps it with the full envelope on read.

## The generic eval contract

`vars/common.yaml` defines control-flow variables used by the remaining `sub_*` tasks:

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

1. Add an entry to `SUBSYSTEM` in [`vars/common.yaml`](/vars/common.yaml). Set `requested` only if the trigger logic differs from `<NAME> is truthy`. Put contrib data under `contrib`.

2. Create a `gen_<name>.tasks` file following the pattern above — read from `lookup('subsys', id='<name>')`, guard with `get='active'`.

3. Add the `gen_*.tasks` import to [`tasks/compfuzor.includes`](/tasks/compfuzor.includes) with a `when:` guard matching the trigger condition.

4. If you need validation, create a `sub_<name>.tasks` that publishes a minimal record into `SUBSYSTEM` before the `gen_*.tasks` import.

## File map

| File | Purpose |
|------|---------|
| [`vars/common.yaml`](/vars/common.yaml) | Static `SUBSYSTEM` defs, helper vars, generic eval contract |
| [`library/lookup_plugins/subsys.py`](/library/lookup_plugins/subsys.py) | Lookup: resolves envelope from SUBSYSTEM + env vars |
| [`library/lookup_plugins/merge_subsys.py`](/library/lookup_plugins/merge_subsys.py) | Lookup: merges subsystem contrib artifacts into globals |
| [`library/filter_plugins/merge.py`](/library/filter_plugins/merge.py) | Direct list/dict merge helpers and raw-copy primitives |
| [`library/filter_plugins/build_install_bins.py`](/library/filter_plugins/build_install_bins.py) | `build_install_bins` filter (used by kernel) |
| [`tasks/compfuzor/sub_get_urls.tasks`](/tasks/compfuzor/sub_get_urls.tasks) | Validates and publishes get_urls subsystem |
| [`tasks/compfuzor/sub_kernel.tasks`](/tasks/compfuzor/sub_kernel.tasks) | Validates and publishes kernel subsystems |
| [`tasks/compfuzor/gen_*.tasks`](/tasks/compfuzor/) | Merge subsystem contrib into host facts |
