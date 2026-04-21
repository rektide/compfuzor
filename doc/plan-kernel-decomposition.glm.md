# kernel / zswap Decomposition Plan

## Current State

`vars_kernel.tasks` is the most structurally mature file in the tree. It already
demonstrates the intended architecture pattern internally:

1. Contract validation
2. Ordered domain table (`kernelDomains`)
3. Derivation of all outputs from that single table
4. Separation of script bodies into `files/kernel/`

The problem is that it crams all of this into a single `vars_` prefix, hiding
that it does transformation and synthesis, not just foundation.

### Files involved

| File | Kind | Phase | What it does |
|---|---|---|---|
| [`vars_kernel.tasks`](../tasks/compfuzor/vars_kernel.tasks) | `vars` | compile | Validate + build domain table + derive ETC_FILES/BINS/ENV/PKGS |
| [`kernel_modules.tasks`](../tasks/compfuzor/kernel_modules.tasks) | `fs`-ish | extras-apply | Write `/etc/modules-load.d` config (legacy, simple) |
| [`files/kernel/build-*.sh`](../files/kernel/) | support | runtime | Build conf files from JSON artifacts |
| [`files/kernel/install-*.sh`](../files/kernel/) | support | runtime | Apply conf files to system |

The generated bin scripts (`build.sh`, `install.sh`, `build-kernel.sh`, etc.)
do the actual work at runtime. `vars_kernel` sets up the data contract and
registers those scripts.

### The playbook: [`zswap.etc.pb`](../zswap.etc.pb)

```yaml
KERNEL_MODULES:
  zswap:
    params:
      enabled: Y
      compressor: lz4
      zpool: z3fold
      max_pool_percent: "20"
      accept_threshold_percent: "90"
      same_filled_pages_enabled: Y
      exclusive_loads: Y
```

This is a clean declarative card. The decomposition does not change it.

## Problem Analysis

`vars_kernel.tasks` conflates three semantic layers:

1. **Validation** (lines 27-50): Contract checking — this is transform work
2. **Domain table + derivation** (lines 70-153): The ordered domain table is a
   `spec_`, and deriving ETC_FILES/BINS/ENV/PKGS from it is synthesis
3. **Bin script registration**: This is synthesis output, not foundation

The file is well-structured internally. The decomposition is about giving each
layer its correct prefix, not about restructuring the logic.

One additional gap: `kernel_modules.tasks` (the extras-apply execution step)
only handles `MODULES`-style module loading, not the full kernel subsystem.
The actual execution is delegated to the generated install scripts run through
`bins_run`. This is an unusual pattern worth preserving — the kernel subsystem
uses generated scripts as its execution surface rather than direct Ansible
modules.

## Proposed Decomposition

### `fn_kernel.tasks` — Transform

| Facet | Value |
|---|---|
| kind | `fn` |
| class | `transform` |
| phase | `compile` |
| effect | `none` |
| apply | `kernel` |

Responsibility: validate contract, normalize inputs into domain-shaped specs.

What it would do:
- Validate `KERNEL_MODULES` is a mapping, entries are mappings, params are mappings
- Validate `KERNEL_SYSCTL` is a mapping
- Validate `KERNEL_SYSFS` is a mapping
- Produce `_fn_kernel_out` with normalized domain data:

```yaml
_fn_kernel_out:
  modules:
    zswap:
      load: true
      params:
        enabled: Y
        compressor: lz4
        ...
  sysctl: {}
  sysfs: {}
```

This is extraction of the validation block (lines 27-50) plus normalization.

### `gen_kernel.tasks` — Synthesis

| Facet | Value |
|---|---|
| kind | `syn` |
| class | `synthesis` |
| phase | `compile` |
| effect | `none` |
| apply | `kernel` |

Responsibility: consume normalized spec, build the ordered domain table, derive
all pipeline artifacts. This is the core of the current `vars_kernel.tasks`.

What it would do:
- Read `_fn_kernel_out`
- Build `kernelDomains` ordered table (current lines 70-117)
- Filter to `activeKernelDomains`
- Derive `ETC_FILES`, `BINS`, `ENV`, `PKGS` from the table (current lines 124-154)
- Emit `_syn_kernel` envelope signaling what domains are active

This preserves the domain table pattern that makes `vars_kernel` structurally
strong, but gives it the correct prefix. The ordered table is the synthesis
blueprint. The derived facts are the synthesis output.

### `vars_kernel.tasks` — Foundation (slimmed)

| Facet | Value |
|---|---|
| kind | `vars` |
| class | `foundation` |
| phase | `compile` |
| effect | `none` |
| apply | `kernel` |

Responsibility: only the base defaults and flags that other kernel files need.

What remains:
- Set `KERNEL_BYPASS` default if needed
- Set any base directory conventions specific to kernel
- Signal kernel subsystem activation (`hasKernelDomains` flag)

This becomes ~10 lines. A thin foundation that the fn and gen files build on.

### Execution: no changes needed

The generated scripts in `files/kernel/` and the `kernel_modules.tasks` extras
step stay as-is. The kernel subsystem already uses the correct execution
pattern: data artifacts (JSON) + generated programs (bin scripts) that consume
them.

## Data Flow

```
KERNEL_MODULES / KERNEL_SYSCTL / KERNEL_SYSFS
  (raw playbook input)
  │
  ▼
vars_kernel.tasks (slim foundation)
  base defaults
  │
  ▼
fn_kernel.tasks
  validate + normalize → _fn_kernel_out
  │
  ▼
gen_kernel.tasks
  build domain table
  derive ETC_FILES, BINS, ENV, PKGS
  emit _syn_kernel
  │
  ▼
  (pipeline continues: ETC_FILES → fs_base, BINS → bins, etc.)
  │
  ▼
extras-apply: kernel_modules.tasks (legacy MODULES support)
  bins_run: build.sh → install.sh (primary execution surface)
```

## .includes Wiring

Current:
```yaml
- import_tasks: compfuzor/vars_kernel.tasks
  when: KERNEL_MODULES is defined or KERNEL_MODPROBE is defined or ...
  tags: ['vars', 'always']
```

Proposed:
```yaml
- import_tasks: compfuzor/vars_kernel.tasks
  when: KERNEL_MODULES is defined or KERNEL_SYSCTL is defined or KERNEL_SYSFS is defined
  tags: ['vars', 'always']
- import_tasks: compfuzor/fn_kernel.tasks
  when: KERNEL_MODULES is defined or KERNEL_SYSCTL is defined or KERNEL_SYSFS is defined
  tags: ['vars', 'always']
- import_tasks: compfuzor/gen_kernel.tasks
  when: _fn_kernel_out is defined
  tags: ['vars', 'always']
```

The extras-apply block stays unchanged:
```yaml
- import_tasks: compfuzor/kernel_modules.tasks
  when: MODULES|default(False) is truthy
```

## Why This Matters For zswap.etc.pb

The playbook stays identical:

```yaml
KERNEL_MODULES:
  zswap:
    params:
      enabled: Y
      compressor: lz4
      ...
```

But the pipeline processing it becomes:

```
vars_kernel  →  "kernel subsystem active"
fn_kernel    →  "validated: zswap module with 7 params, no sysctl, no sysfs"
gen_kernel   →  "derived: 1 JSON artifact, 4 bin scripts, 3 env vars, 1 pkg"
```

Each step is inspectable. If a new contributor asks "where does validation
happen" or "where are the bin scripts registered", the prefix answers
immediately. Today both answers are "somewhere in vars_kernel.tasks".

## Migration Path

1. Extract validation into `fn_kernel.tasks` — can run alongside current code
2. Extract domain table + derivation into `gen_kernel.tasks`
3. Slim `vars_kernel.tasks` to base defaults only
4. Update `.includes` wiring
5. Remove `KERNEL_MODPROBE` and `KERNEL_PARAMS` from the when-clause if they
   are unused (currently in the gate but not in the contract)

Steps 1-2 can be validated by asserting that the derived ETC_FILES/BINS/ENV/PKGS
are identical before and after. The domain table logic is deterministic — same
inputs, same outputs.

## Structural Note: kernel_modules.tasks

`kernel_modules.tasks` (4 lines) is a legacy execution step that writes
`/etc/modules-load.d` directly via Ansible `copy`. It overlaps with what
`install-kernel.sh` does. Once `gen_kernel` is producing the full domain table
and the install scripts are the primary execution surface, this file could be
retired in favor of the generated script path. Not urgent, but worth noting.
